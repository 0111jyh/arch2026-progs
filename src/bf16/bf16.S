# BFloat16 routines: hand-written RV32I.
#
# uint16_t bf16_from_f32_asm(uint32_t f32bits)   a0 -> a0
# uint16_t bf16_mul_asm(uint16_t a, uint16_t b)  a0, a1 -> a0
# uint16_t bf16_sqrt_asm(uint16_t a)             a0 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tbf16.c.

    .text

    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
    .align  2
bf16_from_f32_asm:
    srli    t0, a0, 23              # t0: 暫存 Exponent
    andi    t0, t0, 255
    li      t1, 255
    beq     t0, t1, bf16_f32_done   # 若exponent都是1，回傳 輸入f32 的高16bits

    srli    t1, a0, 16
    andi    t1, t1, 1               # t1: 高16bits的lsb

    li      t2, 0x7FFF              # Rounding Bias: 0x7FFF
    add     a0, a0, t2
    add     a0, a0, t1

bf16_f32_done:
    srli    a0, a0, 16
    ret

    .size   bf16_from_f32_asm, .-bf16_from_f32_asm

    .globl  bf16_mul_asm
    .type   bf16_mul_asm, @function
    .align  2
bf16_mul_asm:
    # Extract the result sign.
    xor     t0, a0, a1
    li      t6, 0x8000
    and     t0, t0, t6              # t0: Sign

    # Extract exponents and fractions.
    srli    t1, a0, 7
    andi    t1, t1, 255             # t1: Exponent A
    srli    t2, a1, 7
    andi    t2, t2, 255             # t2: Exponent B
    andi    t3, a0, 127             # t3: Mantissa A
    andi    t4, a1, 127             # t4: Mantissa B

    # Handle special values in operand order.
    li      t5, 255
    beq     t1, t5, bf16_mul_special_a
    beq     t2, t5, bf16_mul_special_b

    # Handle signed zero.
    li      t5, 0x7FFF
    and     t6, a0, t5
    beq     t6, zero, bf16_mul_return_zero
    and     t6, a1, t5
    beq     t6, zero, bf16_mul_return_zero

    # Normalize operand A.
    beq     t1, zero, bf16_mul_denorm_a
    ori     t3, t3, 128
    addi    a2, t1, -127
    j       bf16_mul_norm_b

bf16_mul_denorm_a:
    li      a2, -126

bf16_mul_loop_a:
    sltiu   t6, t3, 128
    beq     t6, zero, bf16_mul_norm_b
    slli    t3, t3, 1
    addi    a2, a2, -1
    j       bf16_mul_loop_a

    # Normalize operand B.
bf16_mul_norm_b:
    beq     t2, zero, bf16_mul_denorm_b
    ori     t4, t4, 128
    addi    a3, t2, -127
    j       bf16_mul_start

bf16_mul_denorm_b:
    li      a3, -126

bf16_mul_loop_b:
    sltiu   t6, t4, 128
    beq     t6, zero, bf16_mul_start
    slli    t4, t4, 1
    addi    a3, a3, -1
    j       bf16_mul_loop_b

    # Multiply significands using shift-and-add.
bf16_mul_start:
    li      t5, 0
    mv      a4, t4

bf16_mul_loop:
    andi    t6, a4, 1
    beq     t6, zero, bf16_mul_skip
    add     t5, t5, t3

bf16_mul_skip:
    slli    t3, t3, 1
    srli    a4, a4, 1
    bne     a4, zero, bf16_mul_loop

    # Calculate the unbiased result exponent.
    add     a2, a2, a3

    # Normalize and truncate the product.
    li      t6, 0x8000
    and     t6, t5, t6
    beq     t6, zero, bf16_mul_shift7

    srli    t5, t5, 8
    addi    a2, a2, 1
    j       bf16_mul_exponent

bf16_mul_shift7:
    srli    t5, t5, 7

bf16_mul_exponent:
    addi    a2, a2, 127

    # Exponent overflow.
    li      t6, 255
    bge     a2, t6, bf16_mul_return_inf

    # Exponent underflow.
    bge     zero, a2, bf16_mul_underflow

    # Pack the normalized result.
    slli    a2, a2, 7
    andi    t5, t5, 127
    or      a0, a2, t5
    or      a0, a0, t0
    ret

bf16_mul_underflow:
    li      t6, -6
    blt     a2, t6, bf16_mul_return_zero

    # Shift only the fraction, as specified.
    andi    t5, t5, 127
    li      t6, 1
    sub     t6, t6, a2
    srl     t5, t5, t6
    or      a0, t0, t5
    ret

    # Special case: A is NaN or infinity.
bf16_mul_special_a:
    bne     t3, zero, bf16_mul_return_a

    li      t5, 0x7FFF
    and     t6, a1, t5
    beq     t6, zero, bf16_mul_return_nan
    j       bf16_mul_return_inf

    # Special case: B is NaN or infinity.
bf16_mul_special_b:
    bne     t4, zero, bf16_mul_return_b

    li      t5, 0x7FFF
    and     t6, a0, t5
    beq     t6, zero, bf16_mul_return_nan
    j       bf16_mul_return_inf

bf16_mul_return_a:
    ret

bf16_mul_return_b:
    mv      a0, a1
    ret

bf16_mul_return_nan:
    li      a0, 0x7FC0
    ret

bf16_mul_return_inf:
    li      t6, 0x7F80
    or      a0, t0, t6
    ret

bf16_mul_return_zero:
    mv      a0, t0
    ret
    .size   bf16_mul_asm, .-bf16_mul_asm

    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2
bf16_sqrt_asm:
    # Extract exponent and fraction.
    srli    t0, a0, 7
    andi    t0, t0, 255
    andi    t1, a0, 127

    # NaN and infinity.
    li      t6, 255
    beq     t0, t6, sqrt_special

    # Both signed zeros return positive zero.
    li      t6, 0x7FFF
    and     t6, a0, t6
    beq     t6, zero, sqrt_zero

    # Negative nonzero values return quiet NaN.
    srli    t6, a0, 15
    bne     t6, zero, sqrt_nan

    # Denormals return positive zero.
    beq     t0, zero, sqrt_zero

    # m = 128 + fraction
    # e = exponent - 127
    ori     t2, t1, 128
    addi    t3, t0, -127

    # Make the exponent even.
    andi    t6, t3, 1
    beq     t6, zero, sqrt_even

    slli    t2, t2, 1
    addi    t3, t3, -1

sqrt_even:
    # Result unbiased exponent = e / 2.
    srai    t3, t3, 1

    # Binary search range [90, 256].
    li      t4, 90
    li      t5, 256
    li      t6, 90

sqrt_search:
    # Stop when low > high.
    bltu    t5, t4, sqrt_normalize

    # mid = low + ((high - low) >> 1)
    sub     a1, t5, t4
    srli    a1, a1, 1
    add     a1, a1, t4

    # Compute mid * mid using shift-and-add.
    mv      a3, a1
    mv      a4, a1
    li      a2, 0

sqrt_square_loop:
    andi    a5, a4, 1
    beq     a5, zero, sqrt_square_skip
    add     a2, a2, a3

sqrt_square_skip:
    slli    a3, a3, 1
    srli    a4, a4, 1
    bne     a4, zero, sqrt_square_loop

    # square = (mid * mid) >> 7
    srli    a2, a2, 7

    # Find the largest mid satisfying square <= m.
    bltu    t2, a2, sqrt_too_large

    mv      t6, a1
    addi    t4, a1, 1
    j       sqrt_search

sqrt_too_large:
    addi    t5, a1, -1
    j       sqrt_search

sqrt_normalize:
    # t6 contains the selected integer root.
    li      a1, 256
    bgeu    t6, a1, sqrt_root_large

    li      a1, 128
    bltu    t6, a1, sqrt_root_small
    j       sqrt_pack_exp

sqrt_root_large:
    srli    t6, t6, 1
    addi    t3, t3, 1
    j       sqrt_pack_exp

sqrt_root_small:
    slli    t6, t6, 1
    addi    t3, t3, -1

sqrt_pack_exp:
    # Convert unbiased exponent to stored exponent.
    addi    t3, t3, 127

    li      a1, 255
    bge     t3, a1, sqrt_inf

    bge     zero, t3, sqrt_zero

    # Pack the result.
    slli    t3, t3, 7
    andi    t6, t6, 127
    or      a0, t3, t6
    ret

sqrt_special:
    # Preserve NaN payloads.
    bne     t1, zero, sqrt_return_a

    # +Inf is unchanged; -Inf becomes NaN.
    srli    t6, a0, 15
    bne     t6, zero, sqrt_nan

sqrt_return_a:
    ret

sqrt_nan:
    li      a0, 0x7FC0
    ret

sqrt_inf:
    li      a0, 0x7F80
    ret

sqrt_zero:
    li      a0, 0
    ret
    .size   bf16_sqrt_asm, .-bf16_sqrt_asm
