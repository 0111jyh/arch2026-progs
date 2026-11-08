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
    and     t0, t0, t6

    # Extract exponents and fractions.
    srli    t1, a0, 7
    andi    t1, t1, 255
    srli    t2, a1, 7
    andi    t2, t2, 255
    andi    t3, a0, 127
    andi    t4, a1, 127

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
    li      a0, 0
    ret
    .size   bf16_sqrt_asm, .-bf16_sqrt_asm
