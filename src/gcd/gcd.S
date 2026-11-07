# gcd_u32_asm: binary GCD, hand-written RV32I.
#
# uint32_t gcd_u32_asm(uint32_t a, uint32_t b)   a in a0, b in a1, result in a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tgcd.c.

    .text

    .globl  gcd_u32_asm
    .type   gcd_u32_asm, @function
    .align  2
gcd_u32_asm:
    # if (a == 0) return b;
    beq     a0, zero, return_b

    # if (b == 0) return a;
    beq     a1, zero, done

    # shift = 0
    li      t0, 0

    # First check for common_twos (optimization:減少common_twos中每次的jump指令)
    or      t1, a0, a1
    andi    t1, t1, 1
    bne     t1, zero, common_done

common_twos:
    srli    a0, a0, 1
    srli    a1, a1, 1
    addi    t0, t0, 1

    or      t1, a0, a1
    andi    t1, t1, 1
    beq     t1, zero, common_twos

common_done:
    
make_a_odd:
    andi    t1, a0, 1
    bne     t1, zero, main_loop

    srli    a0, a0, 1
    j       make_a_odd

main_loop:
    # First check for make_b_odd(optimization:減少make_b_odd中每次的jump指令)
    andi    t1, a1, 1
    bne     t1, zero, b_is_odd

make_b_odd:
    srli    a1, a1, 1
    andi    t1, a1, 1
    beq     t1, zero, make_b_odd

b_is_odd:
    # If b < a, use another path.
    bltu    a1, a0, smaller_b

    # Case 1: b >= a
    sub     a1, a1, a0
    bne     a1, zero, main_loop

    # b == 0, restore the common factors.
    sll     a0, a0, t0
    ret

smaller_b:
    # Case 2: b < a
    sub     t2, a0, a1
    mv      a0, a1
    mv      a1, t2
    j       main_loop

return_b:
    mv      a0, a1

done:
    ret

    .size   gcd_u32_asm, .-gcd_u32_asm
