// Compare complete candidate buckets under partial and total launch failures.
#include <pthread.h>
static int test_create(pthread_t *, const pthread_attr_t *, void *(*)(void *), void *);
static int test_join(pthread_t, void **);
#define pthread_create test_create
#define pthread_join test_join
#include "../../src/hardnested.c"
#undef pthread_create
#undef pthread_join
#include <assert.h>
#include <errno.h>

int num_CPUs(void) { return 4; }
static unsigned mode, attempts, failures, live;
static pthread_t launched[1024];

static int test_create(pthread_t *thread, const pthread_attr_t *attr, void *(*start)(void *), void *arg)
{
    if (start == generate_candidates_worker_thread) {
        unsigned index = attempts++ % 4;
        bool fail = mode == 1 ? index == 0 : mode == 2 ? index == 2
                  : mode == 3 ? index == 3 : mode == 4 ? index % 2 == 0 : mode == 5;
        if (fail) {
            ++failures;
            memset(thread, 0xa5, sizeof(*thread));
            return EAGAIN;
        }
    }
    int result = pthread_create(thread, attr, start, arg);
    if (!result) { assert(live < 1024); launched[live++] = *thread; }
    return result;
}

static int test_join(pthread_t thread, void **result)
{
    unsigned index = 0;
    while (index < live && !pthread_equal(launched[index], thread)) ++index;
    assert(index < live); // Never pass an uncreated or already joined ID to pthread_join.
    launched[index] = launched[--live];
    return pthread_join(thread, result);
}

static int compare_buckets(const void *left, const void *right)
{
    const statelist_t *a = left, *b = right;
    for (unsigned side = 0; side < 2; ++side) {
        if (a->len[side] != b->len[side]) return a->len[side] < b->len[side] ? -1 : 1;
        int result = memcmp(a->states[side], b->states[side], a->len[side] * sizeof(uint32_t));
        if (result) return result;
    }
    return 0;
}

static statelist_t *snapshot(unsigned *length)
{
    *length = 0;
    for (statelist_t *p = candidates; p; p = p->next)
        if (p->len[0] && p->len[1]) ++*length;
    statelist_t *result = calloc(*length ? *length : 1, sizeof(*result));
    assert(result);
    unsigned index = 0;
    for (statelist_t *p = candidates; p; p = p->next) {
        if (!p->len[0] || !p->len[1]) continue; // Empty products contain no candidate keys.
        for (unsigned side = 0; side < 2; ++side) {
            result[index].len[side] = p->len[side];
            size_t bytes = p->len[side] * sizeof(uint32_t);
            result[index].states[side] = malloc(bytes);
            assert(result[index].states[side]);
            memcpy(result[index].states[side], p->states[side], bytes);
        }
        ++index;
    }
    qsort(result, *length, sizeof(*result), compare_buckets);
    return result;
}

static void free_snapshot(statelist_t *data, unsigned length)
{
    for (unsigned i = 0; i < length; ++i) { free(data[i].states[0]); free(data[i].states[1]); }
    free(data);
}

int main(int argc, char **argv)
{
    assert(argc == 2);
    FILE *input = fopen(argv[1], "rb");
    assert(input && !fseek(input, 0, SEEK_END));
    long bytes = ftell(input);
    assert(bytes > 0);
    rewind(input);
    char *data = malloc(bytes);
    assert(data && fread(data, 1, bytes, input) == (size_t)bytes);
    fclose(input);
    init_it_all();
    known_target_key = UINT64_MAX;
    init_part_sum_bitarrays();
    init_allbitflips_array();
    init_nonce_memory();
    assert(read_nonces(data, bytes) == 1);
    hardnested_stage = CHECK_1ST_BYTES | CHECK_2ND_BYTES;
    update_nonce_data();
    float depth;
    shrink_key_space(&depth);
    unsigned sum = nonces[best_first_bytes[0]].sum_a8_guess[0].sum_a8_idx;
    statelist_t *expected = NULL;
    unsigned expected_length = 0;
    uint64_t expected_states = 0;
    for (mode = 0; mode < 6; ++mode) {
        attempts = failures = 0;
        generate_candidates(first_byte_Sum, sum);
        assert(attempts == 4 && !live && (mode ? failures > 0 : failures == 0));
        unsigned length;
        statelist_t *actual = snapshot(&length);
        if (!mode) {
            expected = actual;
            expected_length = length;
            expected_states = maximum_states;
            assert(length && maximum_states); // Ensure failures cannot pass by testing empty work.
        } else {
            assert(length == expected_length && maximum_states == expected_states);
            for (unsigned i = 0; i < length; ++i) assert(!compare_buckets(&expected[i], &actual[i]));
            free_snapshot(actual, length);
        }
        free_statelist_cache();
        free_candidates_memory(candidates);
        candidates = NULL;
    }
    free_snapshot(expected, expected_length);
    free_nonces_memory();
    free_part_sum_bitarrays();
    free_bitarray(all_bitflips_bitarray[0]);
    free_bitarray(all_bitflips_bitarray[1]);
    free(data);
    assert(!live);
    puts("Candidate buckets and joins match for first/middle/last/alternating/all launch failures");
}
