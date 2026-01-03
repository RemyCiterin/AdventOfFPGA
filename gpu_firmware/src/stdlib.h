#pragma once

void* malloc(unsigned);
void free(void*);

typedef enum {DEVICE_CPU=0, DEVICE_GPU=1} DEVICE;

// Set the print device as CPU (0) or GPU (1, only availible in verilator)
void set_print_device(int);

void printf(const char*, ...);
void putc(char c);
char getc(void);
void print_int(int x);
unsigned readline(char*, unsigned);


//unsigned strlen(const char*);
void* memset(void*, int, unsigned);
void *memmove(void*, const void*, int);
void *memcpy(void*, const void*, int);
//char* strcpy(char*, const char*);
