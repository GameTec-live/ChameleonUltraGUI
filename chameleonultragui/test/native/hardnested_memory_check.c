// Link like hardnested_tables_check.c. Run with ASan/UBSan as well as -O3.
#include "../../src/hardnested.c"
#include <assert.h>

static uint32_t random_word(void)
{
    static uint32_t state = 0xC1A551C;
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    return state;
}

static void check_bitmap_ownership(void)
{
    const size_t bytes = sizeof(uint32_t) * (1 << 19);
    uint32_t *filter = malloc_bitarray(bytes);
    uint32_t *expected = malloc_bitarray(bytes);
    assert(filter && expected);
    for (unsigned cycle = 0; cycle < 3; ++cycle) {
        init_nonce_memory();
        for (unsigned byte = 0; byte < 256; ++byte)
            for (unsigned side = 0; side < 2; ++side) {
                assert(nonces[byte].states_bitarray[side] == unconstrained_states);
                assert(nonces[byte].num_states_bitarray[side] == (1 << 24));
            }
        for (unsigned kind = 0; kind < 4; ++kind) {
            for (odd_even_t side = EVEN_STATE; side <= ODD_STATE; ++side) {
                for (unsigned i = 0; i < (1 << 19); ++i)
                    filter[i] = kind == 0 ? 0 : kind == 1 ? UINT32_MAX : random_word();
                uint32_t count = count_states(filter);
                unsigned byte = kind == 3 ? 255 : kind;
                memcpy(expected, nonces[byte].states_bitarray[side], bytes);
                uint32_t expected_count = count_bitarray_AND(expected, filter);
                uint32_t actual = intersect_nonce_states(byte, side, filter, count);
                assert(actual == expected_count);
                assert(memcmp(expected, nonces[byte].states_bitarray[side], bytes) == 0);
                assert(count_states(unconstrained_states) == (1 << 24));
                // The second call takes the owned, in-place intersection path.
                for (unsigned i = 0; i < (1 << 19); ++i) filter[i] = random_word();
                expected_count = count_bitarray_AND(expected, filter);
                actual = intersect_nonce_states(byte, side, filter, count_states(filter));
                assert(actual == expected_count);
                assert(memcmp(expected, nonces[byte].states_bitarray[side], bytes) == 0);
            }
        }
        free_nonces_memory();
        assert(unconstrained_states == NULL);
    }
    free_bitarray(filter);
    free_bitarray(expected);
}

static void check_parity_index(void)
{
    init_nonce_memory();
    // Empty, sparse, dense and duplicate second bytes, including inconsistent
    // duplicate parity: lookup must preserve the first list entry's behavior.
    for (unsigned first = 0; first < 256; ++first) {
        for (unsigned n = 0; n < first * 2; ++n) {
            noncelistentry_t *p = malloc(sizeof(*p));
            assert(p);
            p->nonce_enc = (first << 24) | (random_word() & 0xffffff);
            p->par_enc = random_word() & 15;
            p->next = nonces[first].first;
            nonces[first].first = p;
        }
    }
    index_second_byte_parity();
    for (unsigned first = 0; first < 256; ++first)
        for (unsigned second = 0; second < 256; ++second) {
            noncelistentry_t *p = nonces[first].first;
            while (p && ((p->nonce_enc >> 16) & 255) != second) p = p->next;
            assert(second_byte_parity[first][second] == (p ? (p->par_enc >> 2) & 1 : -1));
        }
    free_nonces_memory();
    init_nonce_memory();
    index_second_byte_parity();
    for (unsigned first = 0; first < 256; ++first)
        for (unsigned second = 0; second < 256; ++second)
            assert(second_byte_parity[first][second] == -1);
    free_nonces_memory();
}

static void check_filter_batch(bitflip_filter_t *filters, unsigned count)
{
    run_bitflip_workers(filters, count, true);
    uint32_t bytes = sizeof(uint32_t) * ((1 << 19) + 1);
    uint32_t *expected = malloc_bitarray(bytes);
    assert(expected);
    for (unsigned i = 0; i < count; ++i) {
        bitflip_filter_t *filter = &filters[i];
        bitflip_info input = get_bitflip(filter->side, filter->flip);
        uint32_t decoded = bytes;
        assert(XzDecode(input.input_buffer, input.len, (uint8_t *)expected, &decoded));
        assert(decoded == bytes);
        assert(count_states(expected + 1) == expected[0]);
        bool effective = (float)expected[0] / (1 << 24) < IGNORE_BITFLIP_THRESHOLD;
        assert((filter->bits != NULL) == effective);
        if (effective) {
            assert(filter->count == expected[0]);
            assert(memcmp(expected, filter->bits, bytes) == 0);
        }
        free_bitarray(filter->bits);
    }
    free_bitarray(expected);
}

static void check_filter_counts(void)
{
    bitflip_filter_t filters[BITFLIP_BATCH_SIZE];
    unsigned count = 0;
    for (odd_even_t side = EVEN_STATE; side <= ODD_STATE; ++side)
        for (unsigned flip = 1; flip < 0x400; ++flip) {
            if (!get_bitflip(side, flip).input_buffer) continue;
            filters[count++] = (bitflip_filter_t){NULL, 0, flip, side};
            if (count == BITFLIP_BATCH_SIZE) {
                check_filter_batch(filters, count);
                count = 0;
            }
        }
    if (count) check_filter_batch(filters, count);
}

int main(void)
{
    check_bitmap_ownership();
    check_parity_index();
    check_filter_counts();
    puts("Shared bitmap ownership, full parity index and filter counts passed");
}
