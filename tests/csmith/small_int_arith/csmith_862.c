// Options:   --no-arrays --no-pointers --no-structs --no-unions --argc --no-bitfields --checksum --comma-operators --compound-assignment --concise --consts --divs --embedded-assigns --pre-incr-operator --pre-decr-operator --post-incr-operator --post-decr-operator --unary-plus-operator --jumps --longlong --int8 --uint8 --no-float --main --math64 --muls --safe-math --no-packed-struct --no-paranoid --no-volatiles --no-volatile-pointers --const-pointers --no-builtins --max-array-dim 1 --max-array-len-per-dim 4 --max-block-depth 1 --max-block-size 4 --max-expr-complexity 1 --max-funcs 1 --max-pointer-depth 2 --max-struct-fields 2 --max-union-fields 2 -o csmith_862.c
#include "csmith.h"


static long __undefined;



static int8_t g_3 = (-1L);
static int32_t g_8 = 0x5166941FL;
static int32_t g_9 = 0xC4D1454BL;
static uint16_t g_10 = 7UL;
static int8_t g_13 = 0x61L;



static uint32_t  func_1(void);




static uint32_t  func_1(void)
{ 
    int32_t l_2 = 0xAE9714A0L;
    int32_t l_4 = 0x00F47A6DL;
    if (l_2)
    { 
        uint64_t l_5 = 0UL;
        g_3 = 0x951AD386L;
        l_4 &= l_2;
        ++l_5;
    }
    else
    { 
        g_8 = g_3;
        g_9 = g_8;
        ++g_10;
    }
    g_13 ^= l_2;
    return g_3;
}





int main (int argc, char* argv[])
{
    int print_hash_value = 0;
    if (argc == 2 && strcmp(argv[1], "1") == 0) print_hash_value = 1;
    platform_main_begin();
    crc32_gentab();
    func_1();
    transparent_crc(g_3, "g_3", print_hash_value);
    transparent_crc(g_8, "g_8", print_hash_value);
    transparent_crc(g_9, "g_9", print_hash_value);
    transparent_crc(g_10, "g_10", print_hash_value);
    transparent_crc(g_13, "g_13", print_hash_value);
    platform_main_end(crc32_context ^ 0xFFFFFFFFUL, print_hash_value);
    return 0;
}
