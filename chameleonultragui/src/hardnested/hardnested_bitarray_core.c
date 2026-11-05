//-----------------------------------------------------------------------------
// Copyright (C) 2016, 2017 by piwi
//
// This code is licensed to you under the terms of the GNU GPL, version 2 or,
// at your option, any later version. See the LICENSE.txt file for the text of
// the license.ch b
//-----------------------------------------------------------------------------
// Implements a card only attack based on crypto text (encrypted nonces
// received during a nested authentication) only. Unlike other card only
// attacks this doesn't rely on implementation errors but only on the
// inherent weaknesses of the crypto1 cypher. Described in
//   Carlo Meijer, Roel Verdult, "Ciphertext-only Cryptanalysis on Hardened
//   Mifare Classic Cards" in Proceedings of the 22nd ACM SIGSAC Conference on
//   Computer and Communications Security, 2015
//-----------------------------------------------------------------------------
// some helper functions which can benefit from SIMD instructions or other special instructions
//

#include "hardnested_bitarray_core.h"
#include "hardnested_bf_core.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#ifndef __APPLE__
#include <malloc.h>
#endif

#ifndef __BIGGEST_ALIGNMENT__
#include <stddef.h>
static const size_t __BIGGEST_ALIGNMENT__ = _Alignof(long double);
#endif

#ifdef _MSC_VER
#include <intrin.h> // For __popcnt64
unsigned int __builtin_popcountl(unsigned long long x)
{
    return __popcnt64(x);
}
#endif

uint32_t *malloc_bitarray(uint32_t x)
{
#if defined(_WIN32)
    return __builtin_assume_aligned(_aligned_malloc((x), __BIGGEST_ALIGNMENT__), __BIGGEST_ALIGNMENT__);
#elif defined(__APPLE__)
    uint32_t *allocated_memory;
    if (posix_memalign((void **)&allocated_memory, __BIGGEST_ALIGNMENT__, x))
    {
        return NULL;
    }
    else
    {
        return __builtin_assume_aligned(allocated_memory, __BIGGEST_ALIGNMENT__);
    }
#else
    return __builtin_assume_aligned(memalign(__BIGGEST_ALIGNMENT__, (x)), __BIGGEST_ALIGNMENT__);
#endif
}

void free_bitarray(uint32_t *x)
{
#ifdef _WIN32
    _aligned_free(x);
#else
    free(x);
#endif
}

// Keep population counts inline and vectorizable on CPUs without a baseline
// POPCNT instruction. Calling a scalar runtime helper per word dominates scans.
static inline uint32_t count_word(uint32_t x)
{
#if defined(__GNUC__) && (defined(__arm__) || defined(__aarch64__) || defined(__POPCNT__))
    return __builtin_popcount(x);
#else
    x -= (x >> 1) & 0x55555555u;
    x = (x & 0x33333333u) + ((x >> 2) & 0x33333333u);
    x = (x + (x >> 4)) & 0x0f0f0f0fu;
    return (x * 0x01010101u) >> 24;
#endif
}

uint32_t bitcount(uint32_t a)
{
    return count_word(a);
}

uint32_t count_states(uint32_t *A)
{
    uint32_t count = 0;
    for (uint32_t i = 0; i < (1 << 19); i++)
    {
        count += count_word(A[i]);
    }
    return count;
}

void bitarray_AND(uint32_t *restrict A, uint32_t *restrict B)
{
    A = __builtin_assume_aligned(A, __BIGGEST_ALIGNMENT__);
    B = __builtin_assume_aligned(B, __BIGGEST_ALIGNMENT__);
    for (uint32_t i = 0; i < (1 << 19); i++)
    {
        A[i] &= B[i];
    }
}

void bitarray_low20_AND(uint32_t *restrict A, uint32_t *restrict B)
{
    uint16_t *a = (uint16_t *)__builtin_assume_aligned(A, __BIGGEST_ALIGNMENT__);
    uint16_t *b = (uint16_t *)__builtin_assume_aligned(B, __BIGGEST_ALIGNMENT__);

    for (uint32_t i = 0; i < (1 << 20); i++)
    {
        if (!b[i])
        {
            a[i] = 0;
        }
    }
}

// Fixed-count kernels let compilers vectorize the scan. Fusing filters avoids
// repeatedly reading/writing the destination and counting intermediate states.
#define FILTER_1(i) filters[0][i]
#define FILTER_2(i) (FILTER_1(i) & filters[1][i])
#define FILTER_3(i) (FILTER_2(i) & filters[2][i])
#define FILTER_4(i) (FILTER_3(i) & filters[3][i])
#define FILTER_5(i) (FILTER_4(i) & filters[4][i])
#define FILTER_6(i) (FILTER_5(i) & filters[5][i])
#define FILTER_7(i) (FILTER_6(i) & filters[6][i])
#define FILTER_8(i) (FILTER_7(i) & filters[7][i])
#define FILTER_9(i) (FILTER_8(i) & filters[8][i])
#define FILTER_10(i) (FILTER_9(i) & filters[9][i])
#define FILTER_11(i) (FILTER_10(i) & filters[10][i])
#define FILTER_12(i) (FILTER_11(i) & filters[11][i])
#define FILTER_13(i) (FILTER_12(i) & filters[12][i])
#define FILTER_14(i) (FILTER_13(i) & filters[13][i])
#define FILTER_15(i) (FILTER_14(i) & filters[14][i])
#define FILTER_16(i) (FILTER_15(i) & filters[15][i])
#define FILTER_CASE(n) case n: \
    for (uint32_t i = 0; i < words; ++i) { \
        A[i] &= FILTER_##n(i); \
    } \
    return;

void bitarray_AND_many(uint32_t *restrict A, uint32_t *const *restrict filters, unsigned count, uint32_t words)
{
#if defined(__GNUC__) && defined(__x86_64__)
    // Limit live source-pointer pressure in the x86-64 vectorized kernels.
    if (count > 8) {
        while (count) {
            unsigned batch = count > 8 ? 8 : count;
            bitarray_AND_many(A, filters, batch, words);
            filters += batch;
            count -= batch;
        }
        return;
    }
#endif
    switch (count) {
        case 0: return;
        FILTER_CASE(1)
        FILTER_CASE(2)
        FILTER_CASE(3)
        FILTER_CASE(4)
        FILTER_CASE(5)
        FILTER_CASE(6)
        FILTER_CASE(7)
        FILTER_CASE(8)
        FILTER_CASE(9)
        FILTER_CASE(10)
        FILTER_CASE(11)
        FILTER_CASE(12)
        FILTER_CASE(13)
        FILTER_CASE(14)
        FILTER_CASE(15)
        FILTER_CASE(16)
        default:
            // Larger batches reuse these vectorized kernels on cache-sized
            // slices; the destination stays hot between groups of filters.
            while (count) {
                unsigned batch = count > BITARRAY_MAX_FILTERS ? BITARRAY_MAX_FILTERS : count;
                bitarray_AND_many(A, filters, batch, words);
                filters += batch;
                count -= batch;
            }
            return;
    }
}
#undef FILTER_CASE
#undef FILTER_1
#undef FILTER_2
#undef FILTER_3
#undef FILTER_4
#undef FILTER_5
#undef FILTER_6
#undef FILTER_7
#undef FILTER_8
#undef FILTER_9
#undef FILTER_10
#undef FILTER_11
#undef FILTER_12
#undef FILTER_13
#undef FILTER_14
#undef FILTER_15
#undef FILTER_16

uint32_t count_bitarray_AND(uint32_t *restrict A, uint32_t *restrict B)
{
    // A = __builtin_assume_aligned(A, __BIGGEST_ALIGNMENT__);
    // B = __builtin_assume_aligned(B, __BIGGEST_ALIGNMENT__);
    uint32_t count = 0;
    for (uint32_t i = 0; i < (1 << 19); i++)
    {
        A[i] &= B[i];
        count += count_word(A[i]);
    }
    return count;
}

uint32_t count_bitarray_low20_AND(uint32_t *restrict A, uint32_t *restrict B)
{
    uint32_t count = 0;
    for (uint32_t i = 0; i < (1 << 19); ++i) {
        // Each half-word represents the sixteen low-nibble extensions of one
        // 20-bit state. Keep a group iff B permits at least one extension.
        uint32_t mask = ((0u - ((B[i] & 0xffffu) != 0)) & 0xffffu)
                      | ((0u - ((B[i] >> 16) != 0)) & 0xffff0000u);
        uint32_t value = A[i] & mask;
        A[i] = value;
        count += count_word(value);
    }
    return count;
}

void bitarray_AND4(uint32_t *restrict A, uint32_t *restrict B, uint32_t *restrict C, uint32_t *restrict D)
{
    A = __builtin_assume_aligned(A, __BIGGEST_ALIGNMENT__);
    B = __builtin_assume_aligned(B, __BIGGEST_ALIGNMENT__);
    C = __builtin_assume_aligned(C, __BIGGEST_ALIGNMENT__);
    D = __builtin_assume_aligned(D, __BIGGEST_ALIGNMENT__);
    for (uint32_t i = 0; i < (1 << 19); i++)
    {
        A[i] = B[i] & C[i] & D[i];
    }
}

void bitarray_OR(uint32_t *restrict A, uint32_t *restrict B)
{
    A = __builtin_assume_aligned(A, __BIGGEST_ALIGNMENT__);
    B = __builtin_assume_aligned(B, __BIGGEST_ALIGNMENT__);
    for (uint32_t i = 0; i < (1 << 19); i++)
    {
        A[i] |= B[i];
    }
}

uint32_t count_bitarray_AND2(uint32_t *restrict A, uint32_t *restrict B)
{
    A = __builtin_assume_aligned(A, __BIGGEST_ALIGNMENT__);
    B = __builtin_assume_aligned(B, __BIGGEST_ALIGNMENT__);
    uint32_t count = 0;
    for (uint32_t i = 0; i < (1 << 19); i++)
    {
        count += count_word(A[i] & B[i]);
    }
    return count;
}

uint32_t count_bitarray_AND3(uint32_t *restrict A, uint32_t *restrict B, uint32_t *restrict C)
{
    A = __builtin_assume_aligned(A, __BIGGEST_ALIGNMENT__);
    B = __builtin_assume_aligned(B, __BIGGEST_ALIGNMENT__);
    C = __builtin_assume_aligned(C, __BIGGEST_ALIGNMENT__);
    uint32_t count = 0;
    for (uint32_t i = 0; i < (1 << 19); i++)
    {
        count += count_word(A[i] & B[i] & C[i]);
    }
    return count;
}

uint32_t count_bitarray_AND4(uint32_t *restrict A, uint32_t *restrict B, uint32_t *restrict C, uint32_t *restrict D)
{
    A = __builtin_assume_aligned(A, __BIGGEST_ALIGNMENT__);
    B = __builtin_assume_aligned(B, __BIGGEST_ALIGNMENT__);
    C = __builtin_assume_aligned(C, __BIGGEST_ALIGNMENT__);
    D = __builtin_assume_aligned(D, __BIGGEST_ALIGNMENT__);
    uint32_t count = 0;
    for (uint32_t i = 0; i < (1 << 19); i++)
    {
        count += count_word(A[i] & B[i] & C[i] & D[i]);
    }
    return count;
}
