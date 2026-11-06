//-----------------------------------------------------------------------------
// Copyright (C) 2016, 2017 by piwi
//
// This code is licensed to you under the terms of the GNU GPL, version 2 or,
// at your option, any later version. See the LICENSE.txt file for the text of
// the license.
//-----------------------------------------------------------------------------
// Implements a card only attack based on crypto text (encrypted nonces
// received during a nested authentication) only. Unlike other card only
// attacks this doesn't rely on implementation errors but only on the
// inherent weaknesses of the crypto1 cypher. Described in
//   Carlo Meijer, Roel Verdult, "Ciphertext-only Cryptanalysis on Hardened
//   Mifare Classic Cards" in Proceedings of the 22nd ACM SIGSAC Conference on
//   Computer and Communications Security, 2015
//-----------------------------------------------------------------------------
//
// brute forcing is based on @aczids bitsliced brute forcer
// https://github.com/aczid/crypto1_bs with some modifications. Mainly:
// - don't rollback. Start with 2nd byte of nonce instead
// - reuse results of filter subfunctions
// - reuse results of previous nonces if some first bits are identical
//
//-----------------------------------------------------------------------------
// aczid's Copyright notice:
//
// Bit-sliced Crypto-1 brute-forcing implementation
// Builds on the data structures returned by CraptEV1 craptev1_get_space(nonces, threshold, uid)
/*
Copyright (c) 2015-2016 Aram Verstegen

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*/

#ifndef HARDNESTED_BITARRAY_CORE_H__
#define HARDNESTED_BITARRAY_CORE_H__

#include <stdint.h>

// GNU IFUNC dispatch is limited to Linux/glibc x86-64. Other targets retain the
// portable kernels, and tests can select them with HN_DISABLE_SIMD.
#if defined(__GNUC__) && __GNUC__ >= 6 && !defined(__clang__) && defined(__linux__) && defined(__GLIBC__) && defined(__x86_64__) && !defined(HN_DISABLE_SIMD)
#define HN_SIMD __attribute__((target_clones("avx2", "default")))
#else
#define HN_SIMD
#endif

uint32_t *malloc_bitarray(uint32_t x);
void free_bitarray(uint32_t *x);
uint32_t bitcount(uint32_t a);
uint32_t count_states(uint32_t *A);
void bitarray_AND(uint32_t *A, uint32_t *B);
void bitarray_low20_AND(uint32_t *A, uint32_t *B);
#define BITARRAY_MAX_FILTERS 16
// Apply immutable filters to a word slice; callers count after all batches finish.
void bitarray_AND_many(uint32_t *A, uint32_t *const *filters, unsigned count, uint32_t words);
uint32_t count_bitarray_AND(uint32_t *A, uint32_t *B);
uint32_t count_bitarray_low20_AND(uint32_t *A, uint32_t *B);
void bitarray_AND4(uint32_t *A, uint32_t *B, uint32_t *C, uint32_t *D);
void bitarray_OR(uint32_t *A, uint32_t *B);
uint32_t count_bitarray_AND2(uint32_t *A, uint32_t *B);
uint32_t count_bitarray_AND3(uint32_t *A, uint32_t *B, uint32_t *C);
uint32_t count_bitarray_AND4(uint32_t *A, uint32_t *B, uint32_t *C, uint32_t *D);

#endif
