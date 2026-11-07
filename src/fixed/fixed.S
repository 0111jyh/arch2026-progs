# op1, op2, op3 and q_mul: hand-written RV32I.
#
# uint32_t op1_asm(uint32_t a, uint32_t b, int *n)   a0, a1, a2 -> a0
# uint32_t op2_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# uint32_t op3_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# int32_t  q_mul_asm(int32_t a, int32_t b)           a0, a1 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. q_mul forms a 64-bit product in a register pair. Tests:
# tests/tfixed.c.

    .text

    .globl  op1_asm
    .type   op1_asm, @function
    .align  2
op1_asm:
    # Keep the pass count in t0.
    li      t0, 0

op1_loop:
    # Stop when no carry remains.
    beq     a1, zero, op1_done

    # Compute the carry for the next pass.
    and     t1, a0, a1
    slli    t1, t1, 1

    # Add without propagating carry.
    xor     a0, a0, a1

    # Update the carry and pass count.
    mv      a1, t1
    addi    t0, t0, 1

    j       op1_loop

op1_done:
    # Store the number of passes.
    sw      t0, 0(a2)
    ret

    .size   op1_asm, .-op1_asm

    .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    sub     a0, a0, a1
    ret
    .size   op2_asm, .-op2_asm

    .globl  op3_asm
    .type   op3_asm, @function
    .align  2
op3_asm:
    and     t0, a0, a1
    xor     t1, a0, a1
    srli    t1, t1, 1
    add     a0, t0, t1
    ret
    .size   op3_asm, .-op3_asm

    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2
q_mul_asm:
    # Initialize the 64-bit multiplicand.
    mv      t0, a0
    srai    t1, a0, 31

    # Multiplier and 64-bit product.
    mv      t2, a1
    li      t3, 0
    li      t4, 0
    li      t5, 32

qmul_loop:
    # Check the lowest multiplier bit.
    andi    a2, t2, 1
    beq     a2, zero, qmul_shift

    # Add the 64-bit multiplicand to the product.
    mv      a3, t3
    add     t3, t3, t0
    sltu    a3, t3, a3
    add     t4, t4, t1
    add     t4, t4, a3

qmul_shift:
    # Shift the 64-bit multiplicand left by one.
    srli    a2, t0, 31
    slli    t1, t1, 1
    or      t1, t1, a2
    slli    t0, t0, 1

    # Process the next multiplier bit.
    srli    t2, t2, 1
    addi    t5, t5, -1
    bne     t5, zero, qmul_loop

    # Correct for a negative signed multiplier.
    bge     a1, zero, qmul_round
    sub     t4, t4, a0

qmul_round:
    # Add 2^19 before shifting.
    li      a2, 0x80000
    mv      a3, t3
    add     t3, t3, a2
    sltu    a3, t3, a3
    add     t4, t4, a3

    # Shift right by 20 and keep the low 32 bits.
    slli    t4, t4, 12
    srli    t3, t3, 20
    or      a0, t4, t3

    ret
    .size   q_mul_asm, .-q_mul_asm
