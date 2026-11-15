// Compile with the recovery shared library. Including the implementation gives
// this exhaustive check access to its internal tables without exporting test APIs.
#include "../../src/hardnested.c"
#include <assert.h>

#ifdef RECOVERY_TEST_CPU_COUNT
int num_CPUs(void) { return RECOVERY_TEST_CPU_COUNT; }
#endif

int main(void)
{
    init_part_sum_bitarrays();
    uint8_t *expected = malloc(1 << 20);
    assert(expected);
    for (odd_even_t side = EVEN_STATE; side <= ODD_STATE; ++side) {
        for (uint32_t state = 0; state < (1 << 20); ++state)
            expected[state] = PartialSumProperty(state, side) / 2;
        for (uint32_t state = 0; state < (1 << 24); ++state) {
            uint32_t word = state >> 5, mask = 0x80000000u >> (state & 31);
            for (unsigned sum = 0; sum < NUM_PART_SUMS; ++sum) {
                assert(!!(part_sum_a0_bitarrays[side][sum][word] & mask) == (sum == expected[state >> 4]));
                assert(!!(part_sum_a8_bitarrays[side][sum][word] & mask) == (sum == expected[state & 0xfffff]));
            }
        }
    }
    free(expected);
    free_part_sum_bitarrays();
    puts("All partial-sum table bits match scalar construction");
    return 0;
}
