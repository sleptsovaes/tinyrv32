/* Freestanding RV32I workloads with host-checked mathematical signatures. */
#ifdef HOST
#include <stdio.h>
#endif
static volatile unsigned char message[] = "123456789";
static volatile int values[] = {9,-7,3,0,12,3,-2,5};
static const int sorted[] = {-7,-2,0,3,3,5,9,12};
static volatile unsigned char buffer[64];
static volatile short halves[8];

static void putc_uart(unsigned char c) {
#ifdef HOST
    putchar(c);
#else
    *(volatile unsigned char *)0x10000000u = c;
#endif
}
static void puts_uart(const char *s) { while (*s) putc_uart((unsigned char)*s++); }

static unsigned crc32(void) {
    unsigned crc=0xffffffffu;
    for (unsigned i=0;i<9;i++) {
        crc ^= message[i];
        for (unsigned bit=0;bit<8;bit++)
            crc=(crc>>1) ^ ((0u-(crc&1u)) & 0xedb88320u);
    }
    return ~crc;
}

int main(void) {
    unsigned errors = crc32() != 0xcbf43926u;
    for (unsigned i=0;i<8;i++)
        for (unsigned j=i+1;j<8;j++)
            if (values[j]<values[i]) { int tmp=values[i]; values[i]=values[j]; values[j]=tmp; }
    for (unsigned i=0;i<8;i++) errors += values[i] != sorted[i];
    unsigned sum=0;
    for (unsigned i=0;i<64;i++) { buffer[i]=(unsigned char)(i^0xa5u); sum+=buffer[i]; }
    errors += sum != 10208u;
    for (unsigned i=0;i<8;i++) halves[i]=(short)((int)i-4);
    for (unsigned i=0;i<8;i++) errors += halves[i] != (int)i-4;
    if (errors) puts_uart("FAIL\n");
    else puts_uart("CRC SORT BUFFER OK\n");
    return (int)errors;
}
