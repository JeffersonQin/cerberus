// Options:   --no-arrays --no-pointers --no-structs --no-unions --argc --no-bitfields --checksum --comma-operators --compound-assignment --concise --consts --divs --embedded-assigns --pre-incr-operator --pre-decr-operator --post-incr-operator --post-decr-operator --unary-plus-operator --jumps --longlong --int8 --uint8 --no-float --main --math64 --muls --safe-math --no-packed-struct --no-paranoid --no-volatiles --no-volatile-pointers --const-pointers --no-builtins --max-array-dim 1 --max-array-len-per-dim 4 --max-block-depth 1 --max-block-size 4 --max-expr-complexity 1 --max-funcs 1 --max-pointer-depth 2 --max-struct-fields 2 --max-union-fields 2 -o csmith_420.c
#include "csmith.h"


static long __undefined;



static int32_t g_4 = 0x90197F0AL;
static uint16_t g_6 = 0x6BAFL;
static uint64_t g_10 = 0x9BF9F36173948B08LL;



static uint64_t  func_1(void);




static uint64_t  func_1(void)
{ 
    uint8_t l_2 = 255UL;
    int32_t l_3 = 0x9AD59E57L;
    uint32_t l_5 = 0x0985A957L;
    int32_t l_13 = 0x4515FDC8L;
    l_3 |= l_2;
    if (g_4)
    { 
        l_5 = g_4;
        if (g_4)
            goto lbl_9;
lbl_9:
        g_6++;
        --g_10;
    }
    else
    { 
        g_4 = g_4;
    }
    return l_13;
}





int main (int argc, char* argv[])
{
    int print_hash_value = 0;
    if (argc == 2 && strcmp(argv[1], "1") == 0) print_hash_value = 1;
    platform_main_begin();
    crc32_gentab();
    func_1();
    transparent_crc(g_4, "g_4", print_hash_value);
    transparent_crc(g_6, "g_6", print_hash_value);
    transparent_crc(g_10, "g_10", print_hash_value);
    platform_main_end(crc32_context ^ 0xFFFFFFFFUL, print_hash_value);
    return 0;
}
