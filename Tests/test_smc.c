#include "../Sources/ThermalSMC.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <sys/socket.h>

// Same request ABI; the test build uses a shared, simulated SMC exclusively.
typedef struct {
    uint32_t key; uint8_t unused[24];
    struct { uint32_t size,type; uint8_t attributes; } info;
    uint8_t result,status,command,pad; uint32_t index; uint8_t bytes[32];
} Request;
typedef struct { double mode, target, temperature, flag; int fail_write, fail_read, unlocked; } Fake;
static Fake *fake;
static int checks;
static void check(int condition,const char *name) { if(!condition) { fprintf(stderr,"FAIL: %s\n",name); exit(1); } checks++; }
static uint32_t code(const char *s) { return ((uint32_t)s[0]<<24)|((uint32_t)s[1]<<16)|((uint32_t)s[2]<<8)|s[3]; }

int mt_test_call(void *input,void *output) {
    Request *in=input,*out=output;
    char key[5]; for(int i=0;i<4;i++) key[i]=in->key>>(24-i*8); key[4]=0;
    int mode=!strcmp(key,"F0Md"), flag=!strcmp(key,"Ftst");
    double value=0;
    if(!strcmp(key,"FNum")) value=1;
    else if(mode) value=fake->mode;
    else if(flag) value=fake->flag;
    else if(!strcmp(key,"F0Mn")) value=1000;
    else if(!strcmp(key,"F0Mx")) value=4900;
    else if(!strcmp(key,"F0Ac")) value=fake->target;
    else if(!strcmp(key,"F0Tg")) value=fake->target;
    else if(key[0]=='T') { if(fake->fail_read) return -1; value=fake->temperature; }
    else return -0x84;
    int integer=mode||flag||!strcmp(key,"FNum");
    if(in->command==9) { out->info.size=integer?1:4; out->info.type=code(integer?"ui8 ":"flt "); return 0; }
    if(in->command==5) { if(integer) out->bytes[0]=(uint8_t)value; else { float f=(float)value; memcpy(out->bytes,&f,4); } return 0; }
    if(in->command==6) {
        if(fake->fail_write) return -1;
        if(mode) {
            if(in->bytes[0]==1 && fake->mode==3 && !fake->unlocked) return -0x82;
            fake->mode=in->bytes[0];
        } else if(flag) { fake->flag=in->bytes[0]; fake->unlocked=fake->flag==1; }
        else if(!strcmp(key,"F0Tg")) { float f; memcpy(&f,in->bytes,4); fake->target=f; }
        else return -1;
        return 0;
    }
    return -1;
}

static pid_t start_helper(int *fd,char *path) {
    char parent[32],uid[32]; snprintf(parent,sizeof(parent),"%d",getpid()); snprintf(uid,sizeof(uid),"%u",getuid());
    static int serial; snprintf(path,104,"/var/tmp/minithermal-%u-%d-test-%d.sock",getuid(),getpid(),serial++);
    pid_t child=fork(); check(child>=0,"spawn helper");
    if(child==0) { char *args[]={"test","--serve",parent,uid,path,NULL}; _exit(mt_helper_main(5,args)); }
    *fd=-1;
    for(int i=0;i<50;i++) { *fd=mt_connect(path); if(*fd>=0) break; usleep(20000); }
    check(*fd>=0,"connect helper"); return child;
}
static void exchange(int fd,const char *command,const char *expected) {
    char reply[256]; check(mt_exchange(fd,command,reply,sizeof(reply))==0,"IPC round trip");
    if(strncmp(reply,expected,strlen(expected))) fprintf(stderr,"response: %s expected: %s\n",reply,expected);
    check(!strncmp(reply,expected,strlen(expected)),command);
}
static void reap(pid_t child) { int status; check(waitpid(child,&status,0)==child,"helper terminated"); }
int main(void) {
    fake=mmap(NULL,sizeof(*fake),PROT_READ|PROT_WRITE,MAP_SHARED|MAP_ANON,-1,0);
    check(fake!=MAP_FAILED,"shared simulated hardware");
    MTValue v={.size=4}; strcpy(v.type,"flt "); check(!mt_encode(&v,2400),"encode float"); check(mt_decode(&v)==2400,"float roundtrip");
    strcpy(v.type,"fpe2"); v.size=2; check(!mt_encode(&v,2400.25),"encode fixed point"); check(mt_decode(&v)==2400.25,"fixed point roundtrip");
    check(mt_encode(&v,16384)!=0,"reject fixed point overflow"); check(mt_encode(&v,NAN)!=0,"reject NaN"); check(mt_encode(&v,-1)!=0,"reject negative");
    strcpy(v.type,"sp78"); v.bytes[0]=0xff; v.bytes[1]=0x80; check(mt_decode(&v)==-0.5,"signed temperature");
    strcpy(v.type,"ui8 "); v.size=1; v.bytes[0]=0; check(mt_decode(&v)==0,"zero auto mode");
    check(mt_safe_rpm(1000,1000,4900,40)==1000,"cool minimum");
    check(mt_safe_rpm(1000,1000,4900,65)==2950,"temperature safety floor");
    check(mt_safe_rpm(1200,1000,4900,85)==4900,"hot maximum");
    check(mt_safe_rpm(8000,1000,4900,40)==4900,"clamp maximum");
    check(isnan(mt_safe_rpm(1000,0,4900,40)),"invalid firmware limits");
    check(isnan(mt_safe_rpm(1000,1000,4900,NAN)),"missing sensor protection");
    fake->mode=3; fake->temperature=40; fake->target=1000;
    check(!mt_set_manual(1800),"M4 diagnostic unlock"); check(fake->mode==1 && fake->flag==1 && fake->target==1800,"manual registers");
    check(!mt_restore_auto(),"restore automatic"); check(fake->mode==0 && fake->flag==0,"clear diagnostic flag");
    fake->fail_write=1; check(mt_set_manual(1800)!=0,"propagate write failure"); fake->fail_write=0;
    int fd; char path[104]; pid_t child=start_helper(&fd,path);
    exchange(fd,"ping","ok auto"); exchange(fd,"set 0","error invalid_rpm"); exchange(fd,"set 4901","error invalid_rpm");
    exchange(fd,"set nan","error invalid_rpm"); exchange(fd,"set 2000 trailing","error invalid_rpm");
    exchange(fd,"set 2000","ok manual 2000"); check(fake->mode==1 && fake->target==2000,"manual hardware state");
    fake->temperature=70; sleep(2); exchange(fd,"ping","ok protected"); check(fake->target>3500,"ramp for rising temperature");
    fake->temperature=96; sleep(2); exchange(fd,"ping","ok thermal_guard"); check(fake->mode==0 && fake->flag==0,"overheat restore");
    fake->temperature=40; exchange(fd,"set 2000","ok manual"); fake->fail_read=1; sleep(2);
    exchange(fd,"ping","ok thermal_guard"); check(fake->mode==0,"sensor loss restore"); fake->fail_read=0;
    exchange(fd,"set 2000","ok manual"); exchange(fd,"auto","ok auto"); check(fake->mode==0,"one click restore");
    exchange(fd,"quit","ok auto"); close(fd); reap(child); check(access(path,F_OK)!=0,"socket cleanup");
    child=start_helper(&fd,path); exchange(fd,"set 2000","ok manual"); close(fd); reap(child); check(fake->mode==0,"client disconnect restore");
    child=start_helper(&fd,path); exchange(fd,"set 2000","ok manual"); kill(child,SIGKILL); reap(child); close(fd);
    for(int i=0;i<40 && fake->mode==1;i++) usleep(100000);
    check(fake->mode==0 && fake->flag==0,"independent watchdog restores after SIGKILL"); unlink(path);
    child=start_helper(&fd,path); exchange(fd,"set 2000","ok manual");
    sleep(12); check(fake->mode==0,"heartbeat expiry restore"); close(fd); reap(child);
    printf("PASS: %d checks; simulated writes only, no real fan changes.\n",checks);
    munmap(fake,sizeof(*fake)); return 0;
}
