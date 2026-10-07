#ifndef THERMAL_SMC_H
#define THERMAL_SMC_H
#include <stdint.h>
#include <stddef.h>

typedef struct {
    uint32_t size;
    char type[5];
    uint8_t bytes[32];
} MTValue;

int mt_open(void);
void mt_close(void);
int mt_read(const char *key, MTValue *value);
int mt_number(const char *key, double *value);
int mt_key_at(uint32_t index, char key[5]);
double mt_decode(const MTValue *value);
int mt_encode(MTValue *value, double number);
int mt_write_number(const char *key, double number);
const char *mt_last_error(void);
int mt_fan_mode_key(char key[5]);
int mt_restore_auto(void);
int mt_set_manual(double rpm);
double mt_safe_rpm(double requested, double minimum, double maximum, double temperature);
double mt_hottest_chip(void);
int mt_connect(const char *path);
int mt_exchange(int fd, const char *request, char *reply, size_t capacity);
int mt_helper_main(int argc, char **argv);
#endif
