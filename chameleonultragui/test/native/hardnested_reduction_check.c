// Snapshot every reduced bitmap and count before brute force. Compile twice,
// with RECOVERY_SOURCE pointing to each implementation; compare output files.
// Define REFERENCE_REDUCTION for the previous eager-table implementation.
#ifndef RECOVERY_SOURCE
#define RECOVERY_SOURCE "../../src/hardnested.c"
#endif
#include RECOVERY_SOURCE
#include <assert.h>
#include <zlib.h>

static gzFile output;
static bool verify;

static void write_word(uint32_t value)
{
    if (verify) {
        uint32_t expected;
        assert(gzread(output, &expected, sizeof(expected)) == sizeof(expected));
        assert(value == expected);
    } else {
        assert(gzwrite(output, &value, sizeof(value)) == sizeof(value));
    }
}

// Canonical run encoding preserves every bit without writing gigabytes of
// identical zero/all-one words. Equal snapshots imply equal full bitmaps.
static void write_bitmap(const uint32_t *bits)
{
    uint32_t run = 1, value = bits[0];
    for (unsigned i = 1; i < (1 << 19); ++i) {
        if (bits[i] == value) {
            ++run;
        } else {
            write_word(run);
            write_word(value);
            value = bits[i];
            run = 1;
        }
    }
    write_word(run);
    write_word(value);
}

int main(int argc, char **argv)
{
    assert(argc == 3 || (argc == 4 && strcmp(argv[3], "--verify") == 0));
    verify = argc == 4;
    FILE *input = fopen(argv[1], "rb");
    assert(input);
    assert(fseek(input, 0, SEEK_END) == 0);
    long length = ftell(input);
    assert(length >= 0 && length <= UINT32_MAX);
    rewind(input);
    char *data = malloc(length ? (size_t)length : 1);
    assert(data && fread(data, 1, length, input) == (size_t)length);
    fclose(input);
    init_it_all();
#ifdef REFERENCE_REDUCTION
    init_bitflip_bitarrays();
#endif
    init_part_sum_bitarrays();
    init_allbitflips_array();
    init_nonce_memory();
    assert(read_nonces(data, length) == 1);
    hardnested_stage = CHECK_1ST_BYTES | CHECK_2ND_BYTES;
#ifdef REFERENCE_REDUCTION
    update_nonce_data(false);
#else
    update_nonce_data();
#endif
    output = gzopen(argv[2], verify ? "rb" : "wb1");
    assert(output);
    for (unsigned byte = 0; byte < 256; ++byte)
        for (unsigned side = 0; side < 2; ++side) {
            write_word(nonces[byte].num_states_bitarray[side]);
            write_bitmap(nonces[byte].states_bitarray[side]);
        }
    for (unsigned side = 0; side < 2; ++side) {
        write_word(num_all_bitflips_bitarray[side]);
        write_bitmap(all_bitflips_bitarray[side]);
        for (unsigned sum = 0; sum < NUM_PART_SUMS; ++sum) {
            write_bitmap(part_sum_a0_bitarrays[side][sum]);
            write_bitmap(part_sum_a8_bitarrays[side][sum]);
        }
    }
    for (unsigned side = 0; side < 2; ++side)
        for (unsigned a = 0; a < NUM_PART_SUMS; ++a)
            for (unsigned b = 0; b < NUM_PART_SUMS; ++b)
                write_word(part_sum_count[side][a][b]);
    if (verify) {
        uint8_t extra;
        assert(gzread(output, &extra, 1) == 0);
    }
    assert(gzclose(output) == Z_OK);
    free(data);
#ifdef REFERENCE_REDUCTION
    free_bitflip_bitarrays();
#endif
    free_nonces_memory();
    free_part_sum_bitarrays();
    free_bitarray(all_bitflips_bitarray[0]);
    free_bitarray(all_bitflips_bitarray[1]);
    puts("Complete reduction snapshot written");
}
