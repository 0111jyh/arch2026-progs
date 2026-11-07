#include "fixed.h"

/* Dummies: every function returns 0. Replace with the real routines. */
uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    *n = 0;

    while (b != 0u) {
        uint32_t carry = (a & b) << 1;
        a = a ^ b;
        b = carry;
        (*n)++;
    }

    return a;
}

uint32_t op2(uint32_t a, uint32_t b)
{
    return a - b;
}

uint32_t op3(uint32_t a, uint32_t b)
{
    return (a & b) + ((a ^ b) >> 1);
}

int32_t q_mul(int32_t a, int32_t b)
{
    uint32_t a_lo = (uint32_t) a;
    uint32_t a_hi = (a < 0) ? UINT32_MAX : 0u;

    uint32_t b_bits = (uint32_t) b;

    uint32_t p_lo = 0;
    uint32_t p_hi = 0;

    for (unsigned i = 0; i < 32; ++i) {
        if ((b_bits & 1u) != 0u) {
            uint32_t old_lo = p_lo;

            p_lo += a_lo;
            p_hi += a_hi + (p_lo < old_lo);
        }

        a_hi = (a_hi << 1) | (a_lo >> 31);
        a_lo <<= 1;
        b_bits >>= 1;
    }

    if (b < 0) {
        p_hi -= (uint32_t) a;
    }

    uint32_t carry = (p_lo >> 19) == 0x1FFFu;

    p_lo += 1u << 19;
    p_hi += carry;

    /* Extract bits 51..20 of the 64-bit shifted product. */
    uint32_t result = (p_hi << 12) | (p_lo >> 20);

    return (int32_t) result;
}
