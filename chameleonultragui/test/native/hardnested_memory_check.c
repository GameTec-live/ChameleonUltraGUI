// Link like hardnested_tables_check.c. Run with ASan/UBSan as well as -O3.
#include <pthread.h>
static int observe_cache_wait(pthread_cond_t *condition, pthread_mutex_t *mutex);
#define pthread_cond_wait observe_cache_wait
#include "../../src/hardnested.c"
#undef pthread_cond_wait
#include <assert.h>

static pthread_cond_t wait_observed = PTHREAD_COND_INITIALIZER;
static bool observe_wait;
static unsigned observed;

static int observe_cache_wait(pthread_cond_t *condition, pthread_mutex_t *mutex)
{
    if (observe_wait) {
        ++observed; // The caller holds statelist_cache_mutex.
        pthread_cond_broadcast(&wait_observed);
    }
    return pthread_cond_wait(condition, mutex);
}

void recovery_set_cancelled(int cancelled);

static uint32_t random_word(void)
{
    static uint32_t state = 0xC1A551C;
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    return state;
}

static void check_fused_intersections(void)
{
    const size_t bytes = sizeof(uint32_t) * (1 << 19);
    enum { filter_count = 33 };
    uint32_t *filters[filter_count];
    uint32_t *actual = malloc_bitarray(bytes);
    uint32_t *expected = malloc_bitarray(bytes);
    assert(actual && expected);
    for (unsigned f = 0; f < filter_count; ++f) {
        filters[f] = malloc_bitarray(bytes);
        assert(filters[f]);
    }
    for (unsigned dense = 0; dense < 2; ++dense) {
        for (unsigned f = 0; f < filter_count; ++f)
            for (unsigned i = 0; i < (1 << 19); ++i)
                filters[f][i] = dense ? random_word() | random_word() | random_word() : random_word();
        // Includes the zero-filter identity and the generic fallback beyond
        // the specialized kernels, plus repeated immutable input pointers.
        for (unsigned count = 0; count <= filter_count; ++count) {
            for (unsigned i = 0; i < (1 << 19); ++i) actual[i] = random_word();
            memcpy(expected, actual, bytes);
            for (unsigned f = 0; f < count; ++f) count_bitarray_AND(expected, filters[f]);
            bitarray_AND_many(actual, filters, count, 1 << 19);
            assert(count_states(actual) == count_states(expected));
            assert(memcmp(actual, expected, bytes) == 0);
        }
    }
    uint32_t *shifted[filter_count];
    for (unsigned f = 0; f < filter_count; ++f) shifted[f] = filters[f] + 1;
    const unsigned lengths[] = {0, 1, 3, 4, 5, 511, 512, 513, 1024, 1025};
    for (unsigned count = 0; count <= filter_count; ++count) {
        for (unsigned n = 0; n < sizeof(lengths) / sizeof(lengths[0]); ++n) {
            unsigned words = lengths[n];
            for (unsigned i = 0; i < 1040; ++i) actual[i] = expected[i] = random_word();
            for (unsigned i = 1; i <= words; ++i)
                for (unsigned f = 0; f < count; ++f) expected[i] &= filters[f][i];
            bitarray_AND_many(actual + 1, shifted, count, words);
            assert(memcmp(actual, expected, 1040 * sizeof(uint32_t)) == 0);
        }
    }
    uint32_t *same[filter_count];
    for (unsigned f = 0; f < filter_count; ++f) same[f] = filters[0];
    set_bitarray24(actual);
    bitarray_AND_many(actual, same, filter_count, 1 << 19);
    assert(count_states(actual) == count_states(filters[0]));
    assert(memcmp(actual, filters[0], bytes) == 0);
    for (unsigned f = 0; f < filter_count; ++f) free_bitarray(filters[f]);
    free_bitarray(actual);
    free_bitarray(expected);
}

static void check_low20_groups(void)
{
    const size_t bytes = sizeof(uint32_t) * (1 << 19);
    uint32_t *a = malloc_bitarray(bytes), *b = malloc_bitarray(bytes), *expected = malloc_bitarray(bytes);
    assert(a && b && expected);
    for (unsigned mode = 0; mode < 4; ++mode) {
        for (unsigned i = 0; i < (1 << 19); ++i) {
            a[i] = random_word();
            // Every possible half-word occurs, including zero and all ones.
            b[i] = (mode & 1 ? 0 : i & 65535u)
                 | (mode & 2 ? 0 : ((i * 40503u) & 65535u) << 16);
            uint32_t value = 0;
            for (unsigned half = 0; half < 2; ++half)
                if ((b[i] >> (16 * half)) & 65535u)
                    value |= ((a[i] >> (16 * half)) & 65535u) << (16 * half);
            expected[i] = value;
        }
        assert(count_bitarray_low20_AND(a, b) == count_states(expected));
        assert(memcmp(a, expected, bytes) == 0);
    }
    free_bitarray(a);
    free_bitarray(b);
    free_bitarray(expected);
}

static void check_match_order(void)
{
    init_it_all();
    for (unsigned i = 1; i < 256; ++i) {
        assert(match_byte_diff[i] == reverse(i));
        assert(match_common_bits[i] == trailing_zeros(reverse(i)));
    }
}

static void check_filter_lookup(void)
{
    const uint8_t *saved = candidate_filter_table;
    candidate_filter_table = crypto1_filter_table();
    for (uint32_t state = 0; state < (1 << 20); ++state) {
        assert(candidate_filter(state) == crypto1_filter(state));
        assert(candidate_filter(state | 0xfff00000u) == crypto1_filter(state | 0xfff00000u));
    }
    candidate_filter_table = NULL;
    for (unsigned i = 0; i < 4096; ++i) {
        uint32_t state = random_word();
        assert(candidate_filter(state) == crypto1_filter(state));
    }
    candidate_filter_table = saved;
}

static void check_candidate_groups(void)
{
    for (uint32_t pattern = 0; pattern < 65536; ++pattern) {
        uint32_t word = pattern | ((pattern * 40503u) << 16);
        for (unsigned alternatives = 1; alternatives <= 16; alternatives *= 2) {
            for (unsigned base = 0; base < 32; base += alternatives) {
                uint32_t expected = 0;
                for (unsigned low = 0; low < alternatives; ++low)
                    if (word & (0x80000000u >> (base + low))) expected |= 0x80000000u >> low;
                assert(candidate_group(word, base, alternatives) == expected);
            }
        }
    }
}

static bool reference_candidate_match(uint8_t byte, uint32_t state, odd_even_t side)
{
    static const uint32_t masks[2][8] = {
        {0xfffff0, 0xfffff8, 0xfffff8, 0xfffffc, 0xfffffc, 0xfffffe, 0xfffffe, 0xffffff},
        {0xfffff0, 0xfffff0, 0xfffff8, 0xfffff8, 0xfffffc, 0xfffffc, 0xfffffe, 0xfffffe}};
    for (unsigned i = 1; i < 256; ++i) {
        unsigned diff = reverse(i), common = trailing_zeros(diff);
        uint32_t mask = masks[side][common];
        bool found = false;
        for (unsigned low = 0; low <= (~mask & 255); ++low) {
            uint32_t other = (state & mask) | low;
            // Preserve the original arithmetic-first evaluation order.
            if (remaining_bits_match(common, diff, state, other, side)
                    && test_bit24(nonces[byte ^ diff].states_bitarray[side], other)) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }
    return true;
}

static void check_candidate_predicates(void)
{
    uint32_t *templates[4], counts[4];
    for (unsigned kind = 0; kind < 4; ++kind) {
        templates[kind] = malloc_bitarray(sizeof(uint32_t) * (1 << 19));
        assert(templates[kind]);
        for (unsigned i = 0; i < (1 << 19); ++i)
            templates[kind][i] = kind == 0 ? UINT32_MAX : kind == 1 ? 0
                                 : kind == 2 ? 1u << (i & 31) : random_word();
        counts[kind] = count_states(templates[kind]);
    }
    state_page_pool_t pool = {0};
    state_bitset_t compact[4];
    for (unsigned kind = 0; kind < 4; ++kind) compact[kind] = state_bitset_build(&pool, templates[kind]);
    state_pool_freeze(&pool);
    const uint8_t *saved = candidate_filter_table;
    for (unsigned iteration = 0; iteration < 12; ++iteration) {
        unsigned mode = iteration % 6;
        bool paged = iteration >= 6;
        init_it_all();
        init_nonce_memory();
        known_target_key = UINT64_MAX;
        candidate_filter_table = mode & 1 ? crypto1_filter_table() : NULL;
        if (paged) init_allbitflips_array();
        for (unsigned byte = 0; byte < 256; ++byte)
            for (unsigned side = 0; side < 2; ++side) {
                unsigned kind = mode < 3 ? mode : (byte + side) % 4;
                nonces[byte].states_bitarray[side] = templates[kind];
                if (paged) {
                    size_t size = STATE_PAGE_COUNT * sizeof(*compact[kind].pages);
                    nonce_bitsets[side][byte].pages = state_alloc(size);
                    memcpy(nonce_bitsets[side][byte].pages, compact[kind].pages, size);
                }
                nonces[byte].num_states_bitarray[side] = mode < 4 ? counts[kind]
                    : (1 << 20) + (mode == 5); // Both sides of the ordering threshold.
            }
        for (unsigned byte = 0; byte < 256; ++byte)
            for (odd_even_t side = EVEN_STATE; side <= ODD_STATE; ++side)
                for (unsigned sample = 0; sample < 4; ++sample) {
                    uint32_t state = sample == 0 ? 0 : sample == 1 ? 0xffffff
                                     : sample == 2 ? 1u << (byte % 24) : random_word() & 0xffffff;
                    assert(all_bitflips_match(byte, state, side) == reference_candidate_match(byte, state, side));
                }
        for (unsigned byte = 0; byte < 256; ++byte)
            for (unsigned side = 0; side < 2; ++side)
                nonces[byte].states_bitarray[side] = unconstrained_states;
        free_nonces_memory();
        if (paged) {
            free_bitarray(all_bitflips_bitarray[0]);
            free_bitarray(all_bitflips_bitarray[1]);
        }
    }
    candidate_filter_table = saved;
    for (unsigned kind = 0; kind < 4; ++kind) free(compact[kind].pages);
    state_pool_free(&pool);
    for (unsigned kind = 0; kind < 4; ++kind) free_bitarray(templates[kind]);
}

static void check_cache_notifications(void)
{
    for (unsigned cancel = 0; cancel < 2; ++cancel) {
        init_it_all();
        init_statelist_cache();
        init_book_of_work();
        pthread_mutex_lock(&statelist_cache_mutex);
        for (unsigned a = 0; a < NUM_PART_SUMS; ++a)
            for (unsigned b = 0; b < NUM_PART_SUMS; ++b)
                for (unsigned side = 0; side < 2; ++side)
                    sl_cache[a][b][side].cache_status = WORK_IN_PROGRESS;
        observe_wait = true;
        observed = 0;
        pthread_mutex_unlock(&statelist_cache_mutex);
        uint16_t args[3] = {0, 0, 1};
        pthread_t worker;
        if (pthread_create(&worker, NULL, generate_candidates_worker_thread, args) != 0) {
            // The launch-failure test intentionally disables all threads.
            observe_wait = false;
            init_statelist_cache();
            return;
        }
        pthread_mutex_lock(&statelist_cache_mutex);
        struct timespec deadline;
        assert(clock_gettime(CLOCK_REALTIME, &deadline) == 0);
        deadline.tv_sec += 10;
        while (!observed) {
            int error = pthread_cond_timedwait(&wait_observed, &statelist_cache_mutex, &deadline);
            assert(error == 0);
        }
        // A notification without a publication must rescan and wait again.
        pthread_cond_broadcast(&statelist_cache_changed);
        while (observed < 2) {
            int error = pthread_cond_timedwait(&wait_observed, &statelist_cache_mutex, &deadline);
            assert(error == 0);
        }
        pthread_mutex_unlock(&statelist_cache_mutex);
        if (cancel) recovery_set_cancelled(1);
        // Simulate the active producer publishing after the waiter is asleep.
        // Respect the production lock order: book first, then cache.
        pthread_mutex_lock(&book_of_work_mutex);
        pthread_mutex_lock(&statelist_cache_mutex);
        for (unsigned a = 0; a < NUM_PART_SUMS; ++a)
            for (unsigned b = 0; b < NUM_PART_SUMS; ++b) {
                for (unsigned side = 0; side < 2; ++side)
                    sl_cache[a][b][side].cache_status = COMPLETED;
                for (unsigned c = 0; c < NUM_PART_SUMS; ++c)
                    for (unsigned d = 0; d < NUM_PART_SUMS; ++d)
                        book_of_work[a][b][c][d] = COMPLETED;
            }
        ++statelist_cache_revision;
        pthread_cond_broadcast(&statelist_cache_changed);
        pthread_mutex_unlock(&statelist_cache_mutex);
        pthread_mutex_unlock(&book_of_work_mutex);
        assert(pthread_join(worker, NULL) == 0);
        observe_wait = false;
        recovery_set_cancelled(0);
        free_statelist_cache();
    }
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

static void check_filter_counts(void)
{
    unsigned count;
    uint8_t *storage;
    compact_filter_t *tables = load_compact_filters(&count, &storage);
    uint32_t bytes = sizeof(uint32_t) * ((1 << 19) + 1);
    uint32_t *expected = malloc_bitarray(bytes);
    assert(expected);
    unsigned found = 0;
    for (unsigned side = 0; side < 2; ++side)
        for (unsigned flip = 1; flip < 1024; ++flip) {
            bitflip_info input = get_bitflip(side, flip);
            if (!input.input_buffer) continue;
            uint32_t length = bytes;
            assert(XzDecode(input.input_buffer, input.len, (uint8_t *)expected, &length));
            assert(length == bytes && count_states(expected + 1) == expected[0]);
            bool effective = (float)expected[0] / (1 << 24) < IGNORE_BITFLIP_THRESHOLD;
            unsigned matches = 0;
            for (unsigned t = 0; t < count; ++t) {
                compact_filter_t *table = &tables[t];
                if (table->side != side || table->flip != flip) continue;
                ++matches;
                assert(table->count == expected[0]);
                for (unsigned page = 0; page < STATE_PAGE_COUNT; ++page) {
                    unsigned id = table->pages[page * 2] | ((unsigned)table->pages[page * 2 + 1] << 8);
                    assert(memcmp(table->words + id * STATE_PAGE_WORDS,
                        expected + 1 + page * STATE_PAGE_WORDS, STATE_PAGE_WORDS * sizeof(uint32_t)) == 0);
                }
            }
            assert(matches == (unsigned)effective);
            found += matches;
        }
    assert(found == count);
    free_bitarray(expected);
    free(tables);
    free(storage);
}

static void check_compact_pages(void)
{
    state_page_pool_t pool = {0};
    uint32_t page[STATE_PAGE_WORDS] = {0};
    assert(state_pool_intern(&pool, page) == 0);
    assert(pool.count == 1);
    for (unsigned sample = 0; sample < 4096; ++sample) {
        for (unsigned i = 0; i < STATE_PAGE_WORDS; ++i) page[i] = random_word();
        uint32_t id = state_pool_intern(&pool, page);
        assert(id == sample + 1);
        assert(state_pool_intern(&pool, page) == id);
        assert(memcmp(state_page(&pool, id), page, sizeof(page)) == 0);
    }
    // Force the hash-equality path with unequal page contents. Equality must
    // still compare every word, even when an index entry claims the same hash.
    uint32_t other[STATE_PAGE_WORDS];
    memcpy(other, page, sizeof(page));
    other[63] ^= 1;
    uint64_t hash = UINT64_C(14695981039346656037);
    for (unsigned i = 0; i < STATE_PAGE_WORDS; ++i) hash = (hash ^ other[i]) * UINT64_C(1099511628211);
    size_t slot = hash & (pool.capacity - 1);
    while (pool.slots[slot].page) slot = (slot + 1) & (pool.capacity - 1);
    pool.slots[slot] = (state_page_slot_t){hash, 4096};
    uint32_t id = state_pool_intern(&pool, other);
    assert(id != 4096 && memcmp(state_page(&pool, id), other, sizeof(other)) == 0);
    assert(state_pool_intern(&pool, other) == id);
    state_pool_freeze(&pool);
    assert(memcmp(state_page(&pool, 4096), page, sizeof(page)) == 0);
    state_pool_free(&pool);
    state_pool_free(&pool);
}

int main(void)
{
    check_compact_pages();
    check_candidate_groups();
    check_cache_notifications();
    check_candidate_predicates();
    check_filter_lookup();
    check_fused_intersections();
    check_low20_groups();
    check_match_order();
    check_bitmap_ownership();
    check_parity_index();
    check_filter_counts();
    puts("Compact pages, packed tables, filters, candidates, cache, ownership and parity checks passed");
}
