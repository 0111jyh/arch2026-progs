#include "bf16.h"

/* Dummies: every function returns 0. Replace with the real routines. */
uint16_t bf16_from_f32(uint32_t f32bits)
{
    // & 0xFFu-> 把sign bit 清成0
    uint32_t exponent = (f32bits >> 23) & 0xFFu;

    // Exponent = 0xFF → Infinity 或 NaN，直接回傳高16bits
    if (exponent == 0xFFu) {
        return (uint16_t) (f32bits >> 16);
    }

    uint32_t lsb = (f32bits >> 16) & 1u;
    uint32_t rounded = f32bits + 0x7FFFu + lsb;

    return (uint16_t) (rounded >> 16);
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    uint32_t sign = (a ^ b) & 0x8000u;

    uint32_t exp_a = (a >> 7) & 0xFFu;
    uint32_t exp_b = (b >> 7) & 0xFFu;

    uint32_t frac_a = a & 0x7Fu;
    uint32_t frac_b = b & 0x7Fu;

    /* Special values: examine a before b. */
    if (exp_a == 0xFFu) {
        if (frac_a != 0)
            return a;

        if ((b & 0x7FFFu) == 0)
            return 0x7FC0u;

        return (uint16_t) (sign | 0x7F80u);
    }

    if (exp_b == 0xFFu) {
        if (frac_b != 0)
            return b;

        if ((a & 0x7FFFu) == 0)
            return 0x7FC0u;

        return (uint16_t) (sign | 0x7F80u);
    }

    /* Zero multiplied by a finite operand. */
    if ((a & 0x7FFFu) == 0 || (b & 0x7FFFu) == 0) {
        return (uint16_t) sign;
    }

    /* Extract significands and unbiased exponents. */
    uint32_t mant_a;
    uint32_t mant_b;
    int32_t e_a;
    int32_t e_b;

    if (exp_a == 0) {
        mant_a = frac_a;
        e_a = -126;

        while (mant_a < 128u) {
            mant_a <<= 1;
            e_a--;
        }
    } else {
        mant_a = 128u + frac_a;
        e_a = (int32_t) exp_a - 127;
    }

    if (exp_b == 0) {
        mant_b = frac_b;
        e_b = -126;

        while (mant_b < 128u) {
            mant_b <<= 1;
            e_b--;
        }
    } else {
        mant_b = 128u + frac_b;
        e_b = (int32_t) exp_b - 127;
    }

    /* Multiply significands using integer arithmetic. */
    uint32_t product = mant_a * mant_b;
    int32_t exponent = e_a + e_b;

    /* Normalize and truncate the product. */
    if (product & 0x8000u) {
        product >>= 8;
        exponent++;
    } else {
        product >>= 7;
    }

    int32_t stored_exp = exponent + 127;

    /* Overflow. */
    if (stored_exp >= 255)
        return (uint16_t) (sign | 0x7F80u);

    /* Underflow and denormal results. */
    if (stored_exp <= 0) {
        if (stored_exp < -6)
            return (uint16_t) sign;

        uint32_t fraction = product & 0x7Fu;
        uint32_t shift = (uint32_t) (1 - stored_exp);

        fraction >>= shift;

        return (uint16_t) (sign | fraction);
    }

    /* Normalized result. */
    return (uint16_t) (sign | ((uint32_t) stored_exp << 7) | (product & 0x7Fu));
}

uint16_t bf16_sqrt(uint16_t a)
{
    (void) a;
    return 0;
}
