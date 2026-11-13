#include "rubik.h"
#include "rubik_lookup.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

struct cube {
    uint8_t p[7];
    uint8_t o[7];
};

/* ===== Step 1: Parse and validate input ===== */

static int parse_state(const char *state, struct cube *c)
{
    if (state == NULL)
        return 0;

    if (strlen(state) != 14)
        return 0;

    unsigned seen = 0;
    unsigned orientation_sum = 0;

    for (int i = 0; i < 7; i++) {
        char ch = state[i];

        if (ch < '1' || ch > '7')
            return 0;

        unsigned value = (unsigned) (ch - '1');
        unsigned bit = 1u << value;

        if ((seen & bit) != 0)
            return 0;

        seen |= bit;
        c->p[i] = (uint8_t) value;
    }

    for (int i = 0; i < 7; i++) {
        char ch = state[i + 7];

        if (ch < '1' || ch > '3')
            return 0;

        unsigned value = (unsigned) (ch - '1');

        c->o[i] = (uint8_t) value;
        orientation_sum += value;
    }

    while (orientation_sum >= 3u)
        orientation_sum -= 3u;

    return orientation_sum == 0u;
}

/* ===== Step 2: Check solved state ===== */

static int is_solved(const struct cube *c)
{
    for (int i = 0; i < 7; i++) {
        if (c->p[i] != (uint8_t) i)
            return 0;

        if (c->o[i] != 0)
            return 0;
    }

    return 1;
}

/* ===== Step 3: Apply one clockwise face turn ===== */

static const uint8_t source[3][7] = {
    {1, 4, 2, 0, 3, 5, 6}, /* R */
    {0, 1, 2, 4, 5, 6, 3}, /* B */
    {0, 2, 5, 3, 1, 4, 6}, /* D */
};

static const uint8_t twist[3][7] = {
    {1, 2, 0, 2, 1, 0, 0},
    {0, 0, 0, 1, 2, 1, 2},
    {0, 0, 0, 0, 0, 0, 0},
};

static struct cube turn(struct cube c, int face)
{
    struct cube next;

    for (int i = 0; i < 7; i++) {
        int from = source[face][i];

        next.p[i] = c.p[from];

        unsigned o = (unsigned) c.o[from] + twist[face][i];

        if (o >= 3u)
            o -= 3u;

        next.o[i] = (uint8_t) o;
    }

    return next;
}

/* ===== State Encoding ===== */

static unsigned permutation_rank(const uint8_t p[7])
{
    static const unsigned factorial[7] = {720, 120, 24, 6, 2, 1, 1};

    unsigned rank = 0;

    for (int i = 0; i < 7; i++) {
        unsigned smaller = 0;

        for (int j = i + 1; j < 7; j++) {
            if (p[j] < p[i])
                smaller++;
        }

        rank += smaller * factorial[i];
    }

    return rank;
}

static unsigned orientation_code(const uint8_t o[7])
{
    unsigned code = 0;

    for (int i = 0; i < 6; i++)
        code = code * 3u + o[i];

    return code;
}

static uint32_t encode_state(const struct cube *c)
{
    return permutation_rank(c->p) * 729u + orientation_code(c->o);
}


/* ===== Lookup Table ===== */

/* Read a 24-bit State ID from the packed table. */
static uint32_t lookup_id_at(uint32_t index)
{
    uint32_t offset = index * 3u;

    return (uint32_t) lookup_packed[offset] |
           ((uint32_t) lookup_packed[offset + 1u] << 8) |
           ((uint32_t) lookup_packed[offset + 2u] << 16);
}

/*
 * Returns:
 *   0..5: Exact shortest distance
 *   -1:   Not found in Depth-5 lookup table
 */
static int lookup_distance(uint32_t state_id)
{
    for (int depth = 0; depth <= 5; depth++) {
        uint32_t left = lookup_offsets[depth];
        uint32_t right = lookup_offsets[depth + 1];

        /* Binary search within this depth layer. */
        while (left < right) {
            uint32_t mid = left + (right - left) / 2u;
            uint32_t value = lookup_id_at(mid);

            if (value < state_id)
                left = mid + 1u;
            else
                right = mid;
        }

        if (left < lookup_offsets[depth + 1] &&
            lookup_id_at(left) == state_id) {
            return depth;
        }
    }

    return -1;
}


/* ===== Restore path using exact distances ===== */

static int restore_path(struct cube cube, uint8_t *path)
{
    int distance = lookup_distance(encode_state(&cube));
    int count = 0;

    if (distance < 0)
        return -1;

    while (distance > 0) {
        int found = 0;

        for (int face = 0; face < 3 && !found; face++) {
            struct cube next = cube;

            for (int power = 0; power < 3; power++) {
                next = turn(next, face);

                int next_distance = lookup_distance(encode_state(&next));

                if (next_distance == distance - 1) {
                    path[count++] = (uint8_t) (face * 3 + power);

                    cube = next;
                    distance = next_distance;
                    found = 1;
                    break;
                }
            }
        }

        if (!found)
            return -1;
    }

    return count;
}


/* ===== DFS + Lookup Table + Move Pruning ===== */

static int search(struct cube c,
                  int remaining,
                  int previous_face,
                  uint8_t *path)
{
    /* Solved state */
    if (is_solved(&c))
        return remaining == 0;

    uint32_t id = encode_state(&c);

    int distance = lookup_distance(id);

    /*
     * Case 1:
     * The current state is in the lookup table.
     */
    if (distance >= 0) {
        if (distance > remaining)
            return 0;

        return restore_path(c, path) == distance;
    }

    /*
     * Case 2:
     * The table contains ALL states with distance <= 5.
     *
     * If we have <= 5 moves left and the state is not
     * in the table, this branch cannot succeed.
     */
    if (remaining <= 5)
        return 0;

    /*
     * Case 3:
     * Continue DFS.
     */
    for (int face = 0; face < 3; face++) {
        if (face == previous_face)
            continue;

        struct cube next = c;

        for (int power = 0; power < 3; power++) {
            next = turn(next, face);

            path[0] = (uint8_t) (face * 3 + power);

            if (search(next, remaining - 1, face, path + 1)) {
                return 1;
            }
        }
    }

    return 0;
}


/* ===== Step 5: Convert path into output string ===== */

static const char *const move_name[9] = {"R",  "R2", "R'", "B", "B2",
                                         "B'", "D",  "D2", "D'"};

static int write_solution(const uint8_t *path,
                          int length,
                          char *out,
                          size_t cap)
{
    size_t needed = 1; /* Final '\0' */

    for (int i = 0; i < length; i++) {
        const char *name = move_name[path[i]];

        if (i > 0)
            needed++;

        needed += (name[1] == '\0') ? 1u : 2u;
    }

    if (cap < needed) {
        if (cap > 0 && out != NULL)
            out[0] = '\0';

        return -2;
    }

    if (out == NULL)
        return -2;

    size_t pos = 0;

    for (int i = 0; i < length; i++) {
        const char *name = move_name[path[i]];

        if (i > 0)
            out[pos++] = ' ';

        out[pos++] = name[0];

        if (name[1] != '\0')
            out[pos++] = name[1];
    }

    out[pos] = '\0';

    return length;
}

/* ===== Step 6: IDDFS solver ===== */

int rubik_solve(const char *state, char *out, size_t cap)
{
    struct cube initial;

    /* Invalid input: do not touch output. */
    if (!parse_state(state, &initial))
        return -1;

    uint8_t path[11];

    /* Iterative deepening: try shortest lengths first. */
    for (int limit = 0; limit <= 11; limit++) {
        if (search(initial, limit, -1, path))
            return write_solution(path, limit, out, cap);
    }

    return -1;
}
