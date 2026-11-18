# rubik_solve_asm: optimal 2x2x2 cube solver, hand-written RV32I.
#
# int rubik_solve_asm(const char *state, char *out, size_t cap)
#                                   a0 = state, a1 = out, a2 = cap; result in a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions, no heap, no recursion. Tests: tests/trubik.c.

    .text

    .globl  rubik_solve_asm
    .type   rubik_solve_asm, @function
    .align  2
rubik_solve_asm:
    # a0 = state
    # a1 = output
    # a2 = capacity
    #
    # Stack layout:
    # 0..13    cube at depth 0
    # 16..29   cube at depth 1
    # 32..45   cube at depth 2
    # 48..61   cube at depth 3
    # 64..67   next_move[4]
    # 80..83   path[4]
    # 112..125 scratch cube A
    # 128..141 scratch cube B
    # 152..184 saved registers
    #
    # DFS limit: 1..3
    # No recursion, mul, div or rem.

    addi sp, sp, -208

    sw ra, 152(sp)
    sw s0, 156(sp)
    sw s1, 160(sp)
    sw s2, 164(sp)
    sw s3, 168(sp)
    sw s4, 172(sp)
    sw s5, 176(sp)
    sw s6, 180(sp)
    sw s7, 184(sp)

    mv s0, a1
    mv s1, a2

    beqz a0, rubik_invalid

    mv t0, a0
    li t1, 0
    li t4, 0
    li t5, 1
    li a3, 0

# ------------------------------------------==
# 1. Parse permutation
# ------------------------------------------==

rubik_perm_loop:
    li t6, 7
    bge t1, t6, rubik_ori_start

    lbu t2, 0(t0)
    addi t3, t2, -49

    sltiu t6, t3, 7
    beqz t6, rubik_invalid

    li t6, 1
    sll t6, t6, t3

    and a4, t4, t6
    bnez a4, rubik_invalid
    or t4, t4, t6

    add a5, sp, t1
    sb t3, 0(a5)

    beq t3, t1, rubik_perm_next
    li t5, 0

rubik_perm_next:
    addi t0, t0, 1
    addi t1, t1, 1
    j rubik_perm_loop

# ------------------------------------------==
# 2. Parse orientation
# ------------------------------------------==

rubik_ori_start:
    li t1, 0

rubik_ori_loop:
    li t6, 7
    bge t1, t6, rubik_ori_done

    lbu t2, 0(t0)
    addi t3, t2, -49

    sltiu t6, t3, 3
    beqz t6, rubik_invalid

    addi a5, sp, 7
    add a5, a5, t1
    sb t3, 0(a5)

    add a3, a3, t3

    beqz t3, rubik_ori_next
    li t5, 0

rubik_ori_next:
    addi t0, t0, 1
    addi t1, t1, 1
    j rubik_ori_loop

rubik_ori_done:
    lbu t2, 0(t0)
    bnez t2, rubik_invalid

rubik_mod3_loop:
    li t6, 3
    blt a3, t6, rubik_mod3_done
    addi a3, a3, -3
    j rubik_mod3_loop

rubik_mod3_done:
    bnez a3, rubik_invalid
    bnez t5, rubik_solved

    # Encode the input cube at sp + 0.
    mv a0, sp
    call rubik_encode_state

    # Check whether its distance is within 5.
    call rubik_lookup_distance_asm

    # Not in the table: use existing DFS.
    blt a0, zero, rubik_start_search

    # Save the shortest distance.
    mv s2, a0

    # Reconstruct move indices into path[] at sp + 80.
    mv a2, a0
    mv a0, sp
    addi a1, sp, 80

    call rubik_reconstruct_asm

    # Defensive check: reconstruction must succeed.
    blt a0, zero, rubik_start_search

    # The original output formatter uses s2 as length.
    j rubik_search_found

# ------------------------------------------==
# 3. Iterative Deepening
# ------------------------------------------==

rubik_start_search:
    li s2, 1               # limit = 1

rubik_new_limit:
    li s3, 0               # depth = 0
    sb zero, 64(sp)        # next_move[0] = 0

# ------------------------------------------==
# 4. Iterative DFS
# ------------------------------------------==

rubik_dfs_loop:
    # Check leaf when depth == limit.
    beq s3, s2, rubik_check_leaf

    # Read next_move[depth].
    addi t0, sp, 64
    add t0, t0, s3
    lbu s4, 0(t0)

    # No more moves to try.
    li t1, 9
    bge s4, t1, rubik_backtrack

    # Advance next_move before exploring child.
    addi t1, s4, 1
    sb t1, 0(t0)

    # Convert move index into face + turns.
    # 0..2 -> R, 3..5 -> B, 6..8 -> D
    li s5, 0
    mv s6, s4

    li t0, 3
    blt s6, t0, rubik_face_ready

    addi s6, s6, -3
    li s5, 1

    li t0, 3
    blt s6, t0, rubik_face_ready

    addi s6, s6, -3
    li s5, 2

rubik_face_ready:
    # s6 = power index 0..2
    # Number of clockwise turns = s6 + 1.
    addi s6, s6, 1

    # Move pruning: reject consecutive same-face moves.
    beqz s3, rubik_apply_move

    addi t0, s3, -1
    addi t1, sp, 80
    add t1, t1, t0
    lbu t2, 0(t1)          # previous move index

    li t3, 0               # previous face
    li t4, 3
    blt t2, t4, rubik_prev_face_ready

    li t3, 1
    li t4, 6
    blt t2, t4, rubik_prev_face_ready

    li t3, 2

rubik_prev_face_ready:
    beq s5, t3, rubik_dfs_loop

# ------------------------------------------==
# 5. Apply selected move
# ------------------------------------------==

rubik_apply_move:
    # Save move into path[depth].
    addi t0, sp, 80
    add t0, t0, s3
    sb s4, 0(t0)

    # source = cube[depth]
    slli t0, s3, 4
    add s7, sp, t0

rubik_turn_power_loop:
    # Alternate scratch buffers.
    addi t0, sp, 112
    beq s7, t0, rubik_use_buffer_b

    mv a1, t0
    j rubik_call_turn

rubik_use_buffer_b:
    addi a1, sp, 128

rubik_call_turn:
    mv a0, s7
    mv a2, s5

    jal ra, rubik_turn_once

    # rubik_turn_once preserves a1.
    # It clobbers temporary registers.
    mv s7, a1

    addi s6, s6, -1
    bnez s6, rubik_turn_power_loop

    # Copy rotated cube to cube[depth + 1].
    addi t0, s3, 1
    slli t0, t0, 4
    add t1, sp, t0

    li t2, 0

rubik_copy_cube:
    li t3, 14
    bge t2, t3, rubik_descend

    add t4, s7, t2
    lbu t5, 0(t4)

    add t6, t1, t2
    sb t5, 0(t6)

    addi t2, t2, 1
    j rubik_copy_cube

rubik_descend:
    addi s3, s3, 1

    # New level begins with move 0.
    addi t0, sp, 64
    add t0, t0, s3
    sb zero, 0(t0)

    j rubik_dfs_loop

# ------------------------------------------==
# 6. Check leaf state
# ------------------------------------------==

rubik_check_leaf:
    # cube pointer = sp + depth * 16
    slli t0, s3, 4
    add t1, sp, t0

    li t2, 0

rubik_check_leaf_loop:
    li t3, 7
    bge t2, t3, rubik_search_found

    add t4, t1, t2

    # p[i] == i?
    lbu t5, 0(t4)
    bne t5, t2, rubik_backtrack

    # o[i] == 0?
    lbu t5, 7(t4)
    bnez t5, rubik_backtrack

    addi t2, t2, 1
    j rubik_check_leaf_loop

# ------------------------------------------==
# 7. Backtracking
# ------------------------------------------==

rubik_backtrack:
    beqz s3, rubik_increase_limit

    addi s3, s3, -1
    j rubik_dfs_loop

rubik_increase_limit:
    addi s2, s2, 1

    li t0, 3
    bge t0, s2, rubik_new_limit

    # Depth > 3 not implemented yet.
    li a0, -1
    j rubik_return

# ------------------------------------------==
# 8. Found: format path[] as a move string
# ------------------------------------------==

rubik_search_found:
    # First calculate required capacity.
    # required = move characters + spaces + NUL.
    li t0, 0
    li t4, 1               # terminating NUL

rubik_count_loop:
    bge t0, s2, rubik_capacity_check

    addi t1, sp, 80
    add t1, t1, t0
    lbu t2, 0(t1)

    # name offset = move * 3
    slli t3, t2, 1
    add t3, t3, t2

    la t1, rubik_move_names
    add t1, t1, t3

    # First character.
    addi t4, t4, 1

    # Optional second character.
    lbu t2, 1(t1)
    beqz t2, rubik_count_space
    addi t4, t4, 1

rubik_count_space:
    # Space before every move except the first.
    beqz t0, rubik_count_next
    addi t4, t4, 1

rubik_count_next:
    addi t0, t0, 1
    j rubik_count_loop

rubik_capacity_check:
    bltu s1, t4, rubik_no_space
    beqz s0, rubik_no_space

    mv t6, s0              # output cursor
    li t0, 0               # path index

rubik_output_loop:
    bge t0, s2, rubik_output_done

    # Insert separating space.
    beqz t0, rubik_output_name

    li t1, 32
    sb t1, 0(t6)
    addi t6, t6, 1

rubik_output_name:
    addi t1, sp, 80
    add t1, t1, t0
    lbu t2, 0(t1)

    slli t3, t2, 1
    add t3, t3, t2

    la t1, rubik_move_names
    add t1, t1, t3

    lbu t2, 0(t1)
    sb t2, 0(t6)
    addi t6, t6, 1

    lbu t2, 1(t1)
    beqz t2, rubik_output_next

    sb t2, 0(t6)
    addi t6, t6, 1

rubik_output_next:
    addi t0, t0, 1
    j rubik_output_loop

rubik_output_done:
    sb zero, 0(t6)
    mv a0, s2
    j rubik_return

# ------------------------------------------==
# 9. Error and solved handling
# ------------------------------------------==

rubik_solved:
    beqz s1, rubik_no_space
    beqz s0, rubik_no_space

    sb zero, 0(s0)
    li a0, 0
    j rubik_return

rubik_no_space:
    beqz s1, rubik_no_space_result
    beqz s0, rubik_no_space_result
    sb zero, 0(s0)

rubik_no_space_result:
    li a0, -2
    j rubik_return

rubik_invalid:
    # Invalid state leaves output unchanged.
    li a0, -1

rubik_return:
    lw ra, 152(sp)
    lw s0, 156(sp)
    lw s1, 160(sp)
    lw s2, 164(sp)
    lw s3, 168(sp)
    lw s4, 172(sp)
    lw s5, 176(sp)
    lw s6, 180(sp)
    lw s7, 184(sp)

    addi sp, sp, 208
    ret

    .size rubik_solve_asm, .-rubik_solve_asm

# -------------------------------------------------=
# rubik_turn_once
#
# Input:
#   a0 = source cube pointer
#   a1 = destination cube pointer
#   a2 = face (0=R, 1=B, 2=D)
#
# Cube layout:
#   bytes 0..6  = permutation
#   bytes 7..13 = orientation
#
# Clobbers t0..t6, a3..a5.
# Leaf function: does not modify sp or ra.
# -------------------------------------------------=

    .type rubik_turn_once, @function
    .align 2

rubik_turn_once:
    # Each face has seven entries.
    # table offset = face * 7 = face * 8 - face
    slli t0, a2, 3
    sub  t0, t0, a2

    la  t1, rubik_source
    add t1, t1, t0

    la  t2, rubik_twist
    add t2, t2, t0

    li t3, 0               # i = 0

rubik_turn_loop:
    li t0, 7
    bge t3, t0, rubik_turn_done

    # from = source[face][i]
    lbu t4, 0(t1)

    # next.p[i] = old.p[from]
    add a3, a0, t4
    lbu t5, 0(a3)

    add a4, a1, t3
    sb  t5, 0(a4)

    # next.o[i] = (old.o[from] + twist) % 3
    lbu t5, 7(a3)
    lbu t6, 0(t2)

    add t5, t5, t6

    sltiu a5, t5, 3
    bnez a5, rubik_turn_store_orientation

    addi t5, t5, -3

rubik_turn_store_orientation:
    sb t5, 7(a4)

    addi t1, t1, 1
    addi t2, t2, 1
    addi t3, t3, 1
    j rubik_turn_loop

rubik_turn_done:
    ret

    .size rubik_turn_once, .-rubik_turn_once


    .globl rubik_encode_state
    .type rubik_encode_state, @function
    .align 2

# a0: pointer to 14-byte decoded cube
# return a0: state ID
# t0: position index
# t1: permutation rank
# t2: orientation code
rubik_encode_state:
    li t0, 0
    li t1, 0

encode_perm_outer:
    li t2, 7
    bge t0, t2, encode_orientation

    # Read p[i].
    add t3, a0, t0
    lbu t4, 0(t3)

    # Count smaller entries to the right.
    addi t5, t0, 1
    li t6, 0

encode_perm_inner:
    li a1, 7
    bge t5, a1, encode_perm_update

    add a2, a0, t5
    lbu a3, 0(a2)

    bgeu a3, t4, encode_perm_skip
    addi t6, t6, 1

encode_perm_skip:
    addi t5, t5, 1
    j encode_perm_inner

encode_perm_update:
    # rank = rank * (7 - i) + digit
    # Repeated addition avoids RV32M multiply.
    li a1, 7
    sub a1, a1, t0
    li a4, 0

encode_perm_scale:
    beq a1, zero, encode_perm_scaled
    add a4, a4, t1
    addi a1, a1, -1
    j encode_perm_scale

encode_perm_scaled:
    add t1, a4, t6
    addi t0, t0, 1
    j encode_perm_outer

encode_orientation:
    # Read o[0] through o[5].
    addi a1, a0, 7
    li t0, 0
    li t2, 0

encode_ori_loop:
    li t3, 6
    bge t0, t3, encode_combine

    # code = code * 3 + o[i]
    slli t3, t2, 1
    add t2, t3, t2

    lbu t4, 0(a1)
    add t2, t2, t4

    addi a1, a1, 1
    addi t0, t0, 1
    j encode_ori_loop

encode_combine:
    # 729 = 512 + 128 + 64 + 16 + 8 + 1
    # ID = permutation_rank * 729 + orientation

    slli t3, t1, 9

    slli t4, t1, 7
    add t3, t3, t4

    slli t4, t1, 6
    add t3, t3, t4

    slli t4, t1, 4
    add t3, t3, t4

    slli t4, t1, 3
    add t3, t3, t4

    add t3, t3, t1
    add a0, t3, t2

    ret

    .size rubik_encode_state, .-rubik_encode_state


    .globl rubik_lookup_distance_asm
    .type rubik_lookup_distance_asm, @function
    .align 2

# a0: encoded state ID
# return a0: distance 0..5, or -1 if absent
#
# a6: target ID
# a5: current depth
# t0: offsets base
# t1: packed data base
# t2: low index
# t3: high index (exclusive)
# t4: middle index
# t5, t6, a1-a4: scratch registers
rubik_lookup_distance_asm:
    mv a6, a0

    la t0, rubik_lookup_offsets
    la t1, rubik_lookup_packed

    li a5, 0

lookup_next_layer:
    li a1, 6
    bge a5, a1, lookup_not_found

    # low = offsets[depth]
    # high = offsets[depth + 1]
    slli a1, a5, 2
    add a1, t0, a1

    lw t2, 0(a1)
    lw t3, 4(a1)

lookup_binary_search:
    # Empty search interval?
    bge t2, t3, lookup_advance_layer

    # mid = low + (high - low) / 2
    sub t4, t3, t2
    srli t4, t4, 1
    add t4, t4, t2

    # Address of packed[mid], each ID uses 3 bytes.
    slli a1, t4, 1
    add a1, a1, t4
    add a1, t1, a1

    # Decode 3-byte little-endian State ID.
    lbu a2, 0(a1)
    lbu a3, 1(a1)
    lbu a4, 2(a1)

    slli a3, a3, 8
    slli a4, a4, 16

    or a2, a2, a3
    or a2, a2, a4

    # Compare packed[mid] with the target ID.
    beq a2, a6, lookup_found

    bltu a2, a6, lookup_search_right

    # packed[mid] > target:
    # Search [low, mid)
    mv t3, t4
    j lookup_binary_search

lookup_search_right:
    # packed[mid] < target:
    # Search [mid + 1, high)
    addi t2, t4, 1
    j lookup_binary_search

lookup_advance_layer:
    addi a5, a5, 1
    j lookup_next_layer

lookup_found:
    mv a0, a5
    ret

lookup_not_found:
    li a0, -1
    ret

    .size rubik_lookup_distance_asm, .-rubik_lookup_distance_asm


    .globl rubik_reconstruct_asm
    .type rubik_reconstruct_asm, @function
    .align 2

# a0 = pointer to decoded 14-byte cube
# a1 = output path (move indices)
# a2 = known lookup distance, 0..5
#
# Return a0 = number of moves, or -1 on failure.
#
# Local stack:
#  0..13   current cube
# 16..29   scratch A
# 32..45   scratch B
# 48..84   saved registers

rubik_reconstruct_asm:
    addi sp, sp, -96

    sw ra, 48(sp)
    sw s0, 52(sp)
    sw s1, 56(sp)
    sw s2, 60(sp)
    sw s3, 64(sp)
    sw s4, 68(sp)
    sw s5, 72(sp)
    sw s6, 76(sp)
    sw s7, 80(sp)
    sw s8, 84(sp)

    mv s0, sp
    mv s1, a1
    mv s2, a2
    li s3, 0

    # Copy input cube to local current cube.
    li t0, 0

reconstruct_initial_copy:
    li t1, 14
    bge t0, t1, reconstruct_next_step

    add t2, a0, t0
    lbu t3, 0(t2)

    add t2, s0, t0
    sb t3, 0(t2)

    addi t0, t0, 1
    j reconstruct_initial_copy

reconstruct_next_step:
    # Stop when lookup distance reaches zero.
    beqz s2, reconstruct_success

    # Try move indices 0..8.
    li s4, 0

reconstruct_try_move:
    li t0, 9
    bge s4, t0, reconstruct_failure

    # Decode move:
    # 0..2 -> R
    # 3..5 -> B
    # 6..8 -> D
    li s5, 0
    mv s6, s4

    li t0, 3
    blt s6, t0, reconstruct_face_ready

    addi s6, s6, -3
    li s5, 1

    li t0, 3
    blt s6, t0, reconstruct_face_ready

    addi s6, s6, -3
    li s5, 2

reconstruct_face_ready:
    # Convert power index to turn count 1..3.
    addi s6, s6, 1

    # Source starts at current cube.
    mv s7, s0

    # First destination is scratch A.
    addi s8, sp, 16

reconstruct_turn_loop:
    mv a0, s7
    mv a1, s8
    mv a2, s5

    call rubik_turn_once

    # The destination becomes the next source.
    mv s7, s8

    addi s6, s6, -1
    beqz s6, reconstruct_evaluate

    # Alternate scratch A and scratch B.
    addi t0, sp, 16
    beq s8, t0, reconstruct_use_b

    addi s8, sp, 16
    j reconstruct_turn_loop

reconstruct_use_b:
    addi s8, sp, 32
    j reconstruct_turn_loop

reconstruct_evaluate:
    # Encode candidate cube.
    mv a0, s7
    call rubik_encode_state

    # Find candidate's shortest distance.
    call rubik_lookup_distance_asm

    # Accept only a move that reduces distance by 1.
    addi t0, s2, -1
    bne a0, t0, reconstruct_reject

    # Save accepted move index to path.
    add t1, s1, s3
    sb s4, 0(t1)

    # Copy accepted candidate into current cube.
    li t0, 0

reconstruct_accept_copy:
    li t1, 14
    bge t0, t1, reconstruct_accept_done

    add t2, s7, t0
    lbu t3, 0(t2)

    add t2, s0, t0
    sb t3, 0(t2)

    addi t0, t0, 1
    j reconstruct_accept_copy

reconstruct_accept_done:
    addi s3, s3, 1
    addi s2, s2, -1
    j reconstruct_next_step

reconstruct_reject:
    addi s4, s4, 1
    j reconstruct_try_move

reconstruct_success:
    mv a0, s3
    j reconstruct_return

reconstruct_failure:
    li a0, -1

reconstruct_return:
    lw ra, 48(sp)
    lw s0, 52(sp)
    lw s1, 56(sp)
    lw s2, 60(sp)
    lw s3, 64(sp)
    lw s4, 68(sp)
    lw s5, 72(sp)
    lw s6, 76(sp)
    lw s7, 80(sp)
    lw s8, 84(sp)

    addi sp, sp, 96
    ret

    .size rubik_reconstruct_asm, .-rubik_reconstruct_asm

# ===== Read-only tables =====

    .section .rodata
    .align 2

rubik_source:
    .byte 1, 4, 2, 0, 3, 5, 6
    .byte 0, 1, 2, 4, 5, 6, 3
    .byte 0, 2, 5, 3, 1, 4, 6

rubik_twist:
    .byte 1, 2, 0, 2, 1, 0, 0
    .byte 0, 0, 0, 1, 2, 1, 2
    .byte 0, 0, 0, 0, 0, 0, 0

rubik_move_names:
    .byte 82, 0, 0        # R
    .byte 82, 50, 0       # R2
    .byte 82, 39, 0       # R'
    .byte 66, 0, 0        # B
    .byte 66, 50, 0       # B2
    .byte 66, 39, 0       # B'
    .byte 68, 0, 0        # D
    .byte 68, 50, 0       # D2
    .byte 68, 39, 0       # D'

    .include "src/rubik/rubik_lookup.inc"
