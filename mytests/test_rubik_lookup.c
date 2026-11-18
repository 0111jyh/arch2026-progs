
#include <stdint.h>

/* Functions implemented in src/rubik/rubik.S */
extern uint32_t rubik_encode_state(const uint8_t *cube);
extern int rubik_lookup_distance_asm(uint32_t state_id);

int main(void)
{
    static const uint8_t solved[14] = {0, 1, 2, 3, 4, 5, 6,
                                       0, 0, 0, 0, 0, 0, 0};

    static const uint8_t cube_r[14] = {1, 4, 2, 0, 3, 5, 6,
                                       1, 2, 0, 2, 1, 0, 0};

    /* Test 1: Solved state ID */
    if (rubik_encode_state(solved) != 0u)
        return 1;

    /* Test 2: R move state ID */
    if (rubik_encode_state(cube_r) != 805242u)
        return 2;

    /* Test 3: Solved distance */
    if (rubik_lookup_distance_asm(0u) != 0)
        return 3;

    /* Test 4: R move distance */
    if (rubik_lookup_distance_asm(805242u) != 1)
        return 4;

    return 0;
}
