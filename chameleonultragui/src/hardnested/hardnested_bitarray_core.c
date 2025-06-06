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
unsigned int __builtin_popcountl(unsigned long long x) {
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

uint32_t bitcount(uint32_t a)
{
    return __builtin_popcountl(a);
}

uint32_t count_states(uint32_t *A)
{
    uint32_t count = 0;
    for (uint32_t i = 0; i < (1 << 19); i++)
    {
        count += __builtin_popcountl(A[i]);
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

uint32_t count_bitarray_AND(uint32_t *restrict A, uint32_t *restrict B)
{
    A = __builtin_assume_aligned(A, __BIGGEST_ALIGNMENT__);
    B = __builtin_assume_aligned(B, __BIGGEST_ALIGNMENT__);
    uint32_t count = 0;
    for (uint32_t i = 0; i < (1 << 19); i++)
    {
        A[i] &= B[i];
        count += __builtin_popcountl(A[i]);
    }
    return count;
}

uint32_t count_bitarray_low20_AND(uint32_t *restrict A, uint32_t *restrict B)
{
    uint16_t *a = (uint16_t *)__builtin_assume_aligned(A, __BIGGEST_ALIGNMENT__);
    uint16_t *b = (uint16_t *)__builtin_assume_aligned(B, __BIGGEST_ALIGNMENT__);
    uint32_t count = 0;

    for (uint32_t i = 0; i < (1 << 20); i++)
    {
        if (!b[i])
        {
            a[i] = 0;
        }
        count += __builtin_popcountl(a[i]);
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
        count += __builtin_popcountl(A[i] & B[i]);
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
        count += __builtin_popcountl(A[i] & B[i] & C[i]);
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
        count += __builtin_popcountl(A[i] & B[i] & C[i] & D[i]);
    }
    return count;
}