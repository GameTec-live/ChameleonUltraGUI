#include "bucketsort.h"
#include <string.h>

// Stable counting sort uses one reusable scratch range instead of 512 fixed
// buckets. Stability also preserves recovery order for sentinel/ambiguous inputs.
void bucket_sort_intersect(uint32_t *const estart, uint32_t *const estop,
                           uint32_t *const ostart, uint32_t *const ostop,
                           bucket_info_t *info, uint32_t *scratch)
{
    uint32_t *start[2] = {estart, ostart};
    uint32_t *stop[2] = {estop, ostop};
    size_t count[2][256] = {{0}};
    for (unsigned side = 0; side < 2; ++side)
        for (uint32_t *p = start[side]; p <= stop[side]; ++p)
            ++count[side][*p >> 24];
    for (unsigned side = 0; side < 2; ++side) {
        size_t offset[257] = {0}, next[256];
        for (unsigned b = 0; b < 256; ++b) {
            offset[b + 1] = offset[b] + count[side][b];
            next[b] = offset[b];
        }
        for (uint32_t *p = start[side]; p <= stop[side]; ++p)
            scratch[next[*p >> 24]++] = *p;
        uint32_t *out = start[side];
        info->numbuckets = 0;
        for (unsigned b = 0; b < 256; ++b) {
            if (!count[0][b] || !count[1][b]) continue;
            unsigned n = info->numbuckets++;
            info->bucket_info[side][n].head = out;
            memcpy(out, scratch + offset[b], count[side][b] * sizeof(*out));
            out += count[side][b];
            info->bucket_info[side][n].tail = out - 1;
        }
    }
}
