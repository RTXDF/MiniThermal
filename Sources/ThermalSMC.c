// SMC wire protocol and M4 sensor keys informed by exelban/Stats (MIT).
// See THIRD_PARTY_NOTICES.md and References/Stats-LICENSE.
#include "ThermalSMC.h"
#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/wait.h>
#include <libproc.h>
#include <poll.h>
#include <unistd.h>
#include <signal.h>
#include <fcntl.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include <errno.h>

typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } SMCVersion;
typedef struct { uint16_t version, length; uint32_t cpu, gpu, memory; } SMCLimits;
typedef struct { uint32_t size, type; uint8_t attributes; } SMCInfo;
typedef struct {
    uint32_t key;
    SMCVersion version;
    SMCLimits limits;
    SMCInfo info;
    uint8_t result, status, command;
    uint32_t index;
    uint8_t bytes[32];
} SMCRequest;
_Static_assert(sizeof(SMCRequest) == 80, "SMC request ABI must be 80 bytes");
_Static_assert(offsetof(SMCRequest, bytes) == 48, "SMC payload offset");

static io_connect_t connection;
static char last_error[192];
static volatile sig_atomic_t stopping;
static const char *chip_keys[] = {
    "Te05", "Te0S", "Te09", "Te0H", "Tp01", "Tp05", "Tp09", "Tp0D",
    "Tp0V", "Tp0Y", "Tp0b", "Tp0e", "Tg0G", "Tg0H", "Tg0K", "Tg0L",
    "Tg0d", "Tg0e", "Tg0j", "Tg0k", "Tg1U", "Tg1k", NULL
};

static uint32_t fourcc(const char *s) {
    return ((uint32_t)(uint8_t)s[0]<<24)|((uint32_t)(uint8_t)s[1]<<16)|
           ((uint32_t)(uint8_t)s[2]<<8)|(uint8_t)s[3];
}
static void key_string(uint32_t n, char *s) {
    for (int i=0; i<4; i++) s[i]=(char)(n >> (24-i*8));
    s[4]=0;
}
static int call(SMCRequest *in, SMCRequest *out) {
    memset(out, 0, sizeof(*out));
#ifdef MT_TESTING
    extern int mt_test_call(void *, void *);
    return mt_test_call(in,out);
#else
    size_t size=sizeof(*out);
    kern_return_t r=IOConnectCallStructMethod(connection, 2, in, sizeof(*in), out, &size);
    if (r != KERN_SUCCESS || out->result) {
        snprintf(last_error, sizeof(last_error), "IOKit 0x%08x / SMC 0x%02x", r, out->result);
        return out->result ? -(int)out->result : -1;
    }
    if (size != sizeof(*out)) { snprintf(last_error, sizeof(last_error), "SMC response size %zu", size); return -1; }
    return 0;
#endif
}
int mt_open(void) {
#ifdef MT_TESTING
    return 0;
#else
    if (connection) return 0;
    io_service_t service=IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) { strcpy(last_error,"AppleSMC unavailable"); return -1; }
    kern_return_t result=IOServiceOpen(service, mach_task_self(), 0, &connection);
    IOObjectRelease(service);
    if (result) { snprintf(last_error,sizeof(last_error),"AppleSMC open 0x%08x",result); connection=0; return -1; }
    return 0;
#endif
}
void mt_close(void) { if (connection) IOServiceClose(connection); connection=0; }
const char *mt_last_error(void) { return last_error; }
static int info(const char *key, SMCInfo *value) {
    if (!key || strlen(key)!=4 || mt_open()) return -1;
    SMCRequest in={0}, out={0}; in.key=fourcc(key); in.command=9;
    int r=call(&in,&out); if (r) return r;
    if (!out.info.size || out.info.size>32) return -1;
    *value=out.info; return 0;
}
int mt_read(const char *key, MTValue *value) {
    SMCInfo metadata; int r=info(key,&metadata); if (r) return r;
    SMCRequest in={0},out={0}; in.key=fourcc(key); in.command=5; in.info.size=metadata.size;
    r=call(&in,&out); if (r) return r;
    memset(value,0,sizeof(*value)); value->size=metadata.size;
    key_string(metadata.type,value->type); memcpy(value->bytes,out.bytes,metadata.size);
    return 0;
}
double mt_decode(const MTValue *v) {
    if (!strcmp(v->type,"flt ") && v->size==4) { float x; memcpy(&x,v->bytes,4); return x; }
    if (!strcmp(v->type,"ui8 ") && v->size==1) return v->bytes[0];
    if (!strcmp(v->type,"ui16") && v->size==2) return (v->bytes[0]<<8)|v->bytes[1];
    if (!strcmp(v->type,"ui32") && v->size==4) return ((uint32_t)v->bytes[0]<<24)|((uint32_t)v->bytes[1]<<16)|((uint32_t)v->bytes[2]<<8)|v->bytes[3];
    if (!strcmp(v->type,"sp78") && v->size==2) return (int16_t)((v->bytes[0]<<8)|v->bytes[1])/256.0;
    if (!strcmp(v->type,"fpe2") && v->size==2) return ((v->bytes[0]<<8)|v->bytes[1])/4.0;
    return NAN;
}
int mt_number(const char *key,double *n) { MTValue v; if (mt_read(key,&v)) return -1; *n=mt_decode(&v); return isfinite(*n)?0:-1; }
int mt_encode(MTValue *v,double n) {
    if (!isfinite(n)||n<0) return -1;
    memset(v->bytes,0,sizeof(v->bytes));
    if (!strcmp(v->type,"flt ") && v->size==4 && n<=20000) { float f=(float)n; memcpy(v->bytes,&f,4); return 0; }
    if (!strcmp(v->type,"ui8 ") && v->size==1 && n<=255 && floor(n)==n) { v->bytes[0]=(uint8_t)n; return 0; }
    if (!strcmp(v->type,"fpe2") && v->size==2 && n<=16383.75) { uint16_t x=(uint16_t)round(n*4); v->bytes[0]=x>>8; v->bytes[1]=x&255; return 0; }
    return -1;
}
int mt_write_number(const char *key,double number) {
    MTValue v; if (mt_read(key,&v)||mt_encode(&v,number)) return -1;
    SMCRequest in={0},out={0}; in.key=fourcc(key); in.command=6; in.info.size=v.size; memcpy(in.bytes,v.bytes,v.size);
    return call(&in,&out);
}
int mt_key_at(uint32_t index,char key[5]) {
    if (mt_open()) return -1;
    SMCRequest in={0},out={0}; in.command=8; in.index=index;
    if (call(&in,&out)) return -1;
    key_string(out.key,key); return 0;
}
int mt_fan_mode_key(char key[5]) {
    double n;
    if (!mt_number("F0Md",&n)) { strcpy(key,"F0Md"); return 0; }
    if (!mt_number("F0md",&n)) { strcpy(key,"F0md"); return 0; }
    return -1;
}
int mt_restore_auto(void) {
    char key[5]; double mode; int ok=1;
    if (mt_fan_mode_key(key) || mt_number(key,&mode)) return -1;
    // Mode 0 and 3 both belong to Apple's controller. Do not touch a system-owned fan.
    if (mode==1 && mt_write_number(key,0)) ok=0;
    double flag;
    if (!mt_number("Ftst",&flag) && flag!=0 && mt_write_number("Ftst",0)) ok=0;
    if (mt_number(key,&mode) || mode==1) ok=0;
    return ok?0:-1;
}
int mt_set_manual(double rpm) {
    char key[5]; double mode;
    if (mt_fan_mode_key(key)||mt_number(key,&mode)) return -1;
    if (mode!=1) {
        int r=mt_write_number(key,1);
        if (r) {
            // Diagnostic unlock is only used when the firmware explicitly rejects the mode.
            if (r!=-0x82 || mt_write_number("Ftst",1)) return -1;
            for (int i=0;i<50 && !stopping;i++) {
                usleep(100000);
                if (!mt_write_number(key,1)) break;
            }
        }
        if (mt_number(key,&mode)||mode!=1) return -1;
    }
    return mt_write_number("F0Tg",rpm);
}
double mt_safe_rpm(double requested,double minimum,double maximum,double temperature) {
    if (!isfinite(requested)||!isfinite(temperature)||!isfinite(minimum)||!isfinite(maximum)||minimum<=0||maximum<minimum) return NAN;
    double ratio=fmax(0,fmin(1,(temperature-50)/30));
    return fmin(maximum,fmax(requested,minimum+(maximum-minimum)*ratio));
}
double mt_hottest_chip(void) {
    double hottest=NAN; int cpu=0,gpu=0;
    for(int i=0;chip_keys[i];i++) {
        double n;
        if (!mt_number(chip_keys[i],&n) && n>0 && n<125) {
            if(i<12) cpu++; else gpu++;
            if(!isfinite(hottest)||n>hottest) hottest=n;
        }
    }
    return cpu && gpu ? hottest : NAN;
}

int mt_connect(const char *path) {
    if (!path || strlen(path)>=sizeof(((struct sockaddr_un *)0)->sun_path)) return -1;
    int fd=socket(AF_UNIX,SOCK_STREAM,0); if (fd<0) return -1;
    struct sockaddr_un address={0}; address.sun_family=AF_UNIX; strlcpy(address.sun_path,path,sizeof(address.sun_path));
    address.sun_len=sizeof(address);
    struct timeval timeout={8,0}; setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));
    int on=1; setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&on,sizeof(on));
    if (connect(fd,(struct sockaddr *)&address,sizeof(address))) { close(fd); return -1; }
    return fd;
}
static int read_line(int fd,char *buffer,size_t capacity) {
    size_t count=0;
    while(count+1<capacity) {
        char c; ssize_t n=read(fd,&c,1); if (n!=1) return -1;
        if (c=='\n') { buffer[count]=0; return 0; }
        buffer[count++]=c;
    }
    return -1;
}
static int write_all(int fd,const char *text) {
    size_t remaining=strlen(text);
    while(remaining) { ssize_t n=write(fd,text,remaining); if(n<=0) return -1; text+=n; remaining-=n; }
    return 0;
}
int mt_exchange(int fd,const char *request,char *reply,size_t capacity) {
    if (write_all(fd,request)||write_all(fd,"\n")) return -1;
    return read_line(fd,reply,capacity);
}
static void stop_signal(int n) { (void)n; stopping=1; }
static int alive(pid_t pid) { return pid>1 && (kill(pid,0)==0 || errno==EPERM); }
static double monotonic(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec+t.tv_nsec/1e9; }
static int guard_process(pid_t helper,pid_t app,int heartbeat) {
    // Independent process restores the fan even if the control helper is killed.
    mt_close(); stopping=0; mt_open(); fcntl(heartbeat,F_SETFL,O_NONBLOCK);
    double last=monotonic(); char b[64];
    for(;;) {
        ssize_t n=read(heartbeat,b,sizeof(b)); if(n>0) last=monotonic();
        if (n==0||stopping||!alive(helper)||!alive(app)||monotonic()-last>12) break;
        sleep(1);
    }
    int restored=-1;
    for(int i=0;i<8 && restored;i++) { restored=mt_restore_auto(); if(restored) sleep(1); }
    mt_close(); close(heartbeat); return restored?1:0;
}
int mt_helper_main(int argc,char **argv) {
    if (argc!=5||strcmp(argv[1],"--serve")) return 64;
#ifndef MT_TESTING
    if(geteuid()!=0) return 64;
#endif
    char *end; long app_long=strtol(argv[2],&end,10); if (*end||app_long<=1||app_long>INT32_MAX) return 64;
    pid_t app=(pid_t)app_long;
    long uid_long=strtol(argv[3],&end,10); if(*end||uid_long<=0||uid_long>UINT32_MAX) return 64;
    uid_t owner=(uid_t)uid_long;
    struct proc_bsdinfo p={0};
    if(proc_pidinfo(app,PROC_PIDTBSDINFO,0,&p,sizeof(p))!=sizeof(p)||p.pbi_uid!=owner) return 64;
#ifndef MT_TESTING
    char model[64]; size_t model_size=sizeof(model);
    if(sysctlbyname("hw.model",model,&model_size,NULL,0)||strcmp(model,"Mac16,10")) return 65;
#endif
    const char *path=argv[4];
    char prefix[64]; snprintf(prefix,sizeof(prefix),"/var/tmp/minithermal-%u-%d-",owner,app);
    if(strncmp(path,prefix,strlen(prefix))||strchr(path+strlen(prefix),'/')||strlen(path)>=104) return 64;
    if(mt_open()) return 69;
    signal(SIGTERM,stop_signal); signal(SIGINT,stop_signal); signal(SIGHUP,stop_signal); signal(SIGPIPE,SIG_IGN);
    double count, minimum, maximum;
    if(mt_number("FNum",&count)||count!=1||mt_number("F0Mn",&minimum)||mt_number("F0Mx",&maximum)||minimum<=0||maximum<=minimum) return 65;
    umask(077);
    int server=socket(AF_UNIX,SOCK_STREAM,0); if(server<0) return 71;
    struct sockaddr_un address={0}; address.sun_family=AF_UNIX; address.sun_len=sizeof(address);
    strlcpy(address.sun_path,path,sizeof(address.sun_path));
    if(bind(server,(struct sockaddr *)&address,sizeof(address))||chown(path,owner,-1)||chmod(path,0600)||listen(server,2)) { close(server); return 71; }
    int pipefd[2]; if(pipe(pipefd)) { close(server); unlink(path); return 71; }
    pid_t guard=fork();
    if(guard==0) { close(server); close(pipefd[1]); _exit(guard_process(getppid(),app,pipefd[0])); }
    close(pipefd[0]);
    if(guard<0) { close(server); close(pipefd[1]); unlink(path); return 71; }
    int client=-1; double last_client=monotonic(), requested=NAN, effective=NAN, last_tick=0;
    char reason[64]="auto"; int failed_restore=0;
    while(!stopping && alive(app)) {
        struct pollfd descriptors[2]={{server,POLLIN,0},{client,POLLIN,0}};
        poll(descriptors,client>=0?2:1,200);
        if(descriptors[0].revents&POLLIN) {
            int incoming=accept(server,NULL,NULL); uid_t uid; gid_t gid; pid_t peer=0; socklen_t len=sizeof(peer);
            if(incoming>=0 && !getpeereid(incoming,&uid,&gid) && uid==owner && !getsockopt(incoming,SOL_LOCAL,LOCAL_PEERPID,&peer,&len) && peer==app && client<0) {
                client=incoming; struct timeval timeout={1,0}; setsockopt(client,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
                setsockopt(client,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout)); last_client=monotonic();
            } else if(incoming>=0) close(incoming);
        }
        if(client>=0 && descriptors[1].revents&(POLLIN|POLLHUP|POLLERR)) {
            char command[96],reply[256];
            if(read_line(client,command,sizeof(command))) { stopping=1; continue; }
            last_client=monotonic();
            if(!strcmp(command,"ping")) {
                snprintf(reply,sizeof(reply),"ok %s %.0f\n",reason,effective);
            } else if(!strcmp(command,"auto") || !strcmp(command,"quit")) {
                requested=NAN; effective=NAN;
                if(mt_restore_auto()) { strcpy(reason,"restore_failed"); failed_restore=1; snprintf(reply,sizeof(reply),"error restore %s\n",mt_last_error()); }
                else { failed_restore=0; strcpy(reason,"auto"); strcpy(reply,"ok auto 0\n"); }
                if(!strcmp(command,"quit")) stopping=1;
            } else if(!strncmp(command,"set ",4)) {
                double rpm=strtod(command+4,&end);
                double temp=mt_hottest_chip();
                if(*end||!isfinite(rpm)||rpm<minimum||rpm>maximum) strcpy(reply,"error invalid_rpm\n");
                else if(!isfinite(temp)||temp>=95) strcpy(reply,"error thermal_guard\n");
                else {
                    effective=mt_safe_rpm(rpm,minimum,maximum,temp);
                    if(mt_set_manual(effective)) {
                        snprintf(reply,sizeof(reply),"error write %s\n",mt_last_error());
                        requested=NAN; effective=NAN; failed_restore=mt_restore_auto()!=0;
                        strcpy(reason,failed_restore?"restore_failed":"write_failed");
                    } else { requested=rpm; strcpy(reason,effective>rpm+1?"protected":"manual"); snprintf(reply,sizeof(reply),"ok %s %.0f\n",reason,effective); }
                }
            } else strcpy(reply,"error unsupported_command\n");
            if(write_all(client,reply)) stopping=1;
        }
        double now=monotonic();
        if(now-last_tick>=1) {
            if(write(pipefd[1],".",1)!=1) { stopping=1; continue; }
            last_tick=now;
            if(isfinite(requested)) {
                double temp=mt_hottest_chip();
                if(!isfinite(temp)||temp>=95||now-last_client>10) {
                    requested=NAN; effective=NAN; failed_restore=mt_restore_auto()!=0;
                    strcpy(reason,failed_restore?"restore_failed":"thermal_guard");
                } else {
                    double next=mt_safe_rpm(requested,minimum,maximum,temp);
                    char key[5]; double mode;
                    if(mt_fan_mode_key(key)||mt_number(key,&mode)||mode!=1) {
                        requested=NAN; effective=NAN; failed_restore=mt_restore_auto()!=0;
                        strcpy(reason,failed_restore?"restore_failed":"system_reclaimed");
                    } else if(fabs(next-effective)>=50) {
                        if(mt_set_manual(next)) { requested=NAN; effective=NAN; failed_restore=mt_restore_auto()!=0; strcpy(reason,failed_restore?"restore_failed":"write_failed"); }
                        else { effective=next; strcpy(reason,effective>requested+1?"protected":"manual"); }
                    }
                }
            }
            if(failed_restore && mt_restore_auto()==0) { failed_restore=0; strcpy(reason,"auto"); }
            if(now-last_client>10) stopping=1;
        }
    }
    for(int i=0;i<5;i++) { if(!mt_restore_auto()) break; usleep(200000); }
    if(client>=0) close(client);
    close(server); unlink(path); close(pipefd[1]);
    waitpid(guard,NULL,0); mt_close(); return 0;
}
