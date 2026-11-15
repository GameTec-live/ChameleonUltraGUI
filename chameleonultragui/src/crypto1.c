/*  crypto1.c

    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License
    as published by the Free Software Foundation; either version 2
    of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
    MA  02110-1301, US

    Copyright (C) 2008-2008 bla <blapost@gmail.com>
*/
#include <stdlib.h>
#include "crapto1.h"
#include "parity.h"

#define SWAPENDIAN(x) \
    (x = (x >> 8 & 0xff00ff) | (x & 0xff00ff) << 8, x = x >> 16 | x << 16)

// Crypto1 keys interleave two 24-bit registers with reversed bits in each
// nibble. These fixed permutations replace per-bit variable-shift loops.
static uint32_t reverse_nibbles(uint32_t x)
{
    x = ((x & 0x555555u) << 1) | ((x >> 1) & 0x555555u);
    return ((x & 0x333333u) << 2) | ((x >> 2) & 0x333333u);
}

static uint64_t spread24(uint32_t value)
{
    uint64_t x = value & 0xffffffu;
    x = (x | (x << 16)) & UINT64_C(0x0000ffff0000ffff);
    x = (x | (x << 8)) & UINT64_C(0x00ff00ff00ff00ff);
    x = (x | (x << 4)) & UINT64_C(0x0f0f0f0f0f0f0f0f);
    x = (x | (x << 2)) & UINT64_C(0x3333333333333333);
    return (x | (x << 1)) & UINT64_C(0x5555555555555555);
}

static uint32_t compact24(uint64_t x)
{
    x &= UINT64_C(0x5555555555555555);
    x = (x | (x >> 1)) & UINT64_C(0x3333333333333333);
    x = (x | (x >> 2)) & UINT64_C(0x0f0f0f0f0f0f0f0f);
    x = (x | (x >> 4)) & UINT64_C(0x00ff00ff00ff00ff);
    x = (x | (x >> 8)) & UINT64_C(0x0000ffff0000ffff);
    return (uint32_t)(x | (x >> 16)) & 0xffffffu;
}

void crypto1_init(struct Crypto1State *state, uint64_t key)
{
    if (state == NULL) return;
    state->odd = reverse_nibbles(compact24(key >> 1));
    state->even = reverse_nibbles(compact24(key));
}

void crypto1_deinit(struct Crypto1State *state)
{
    state->odd = 0;
    state->even = 0;
}

#if !defined(__arm__) || defined(__linux__) || defined(_WIN32) || defined(__APPLE__) // bare metal ARM Proxmark lacks calloc()/free()
struct Crypto1State *crypto1_create(uint64_t key)
{
    struct Crypto1State *state = calloc(sizeof(*state), sizeof(uint8_t));
    if (!state)
        return NULL;
    crypto1_init(state, key);
    return state;
}

void crypto1_destroy(struct Crypto1State *state)
{
    free(state);
}
#endif

void crypto1_get_lfsr(struct Crypto1State *state, uint64_t *lfsr)
{
    *lfsr = (spread24(reverse_nibbles(state->odd)) << 1) |
            spread24(reverse_nibbles(state->even));
}

uint8_t crypto1_bit(struct Crypto1State *s, uint8_t in, int is_encrypted)
{
    uint32_t feedin, t;
    uint8_t ret = crypto1_filter(s->odd);

    feedin = ret & (!!is_encrypted);
    feedin ^= !!in;
    feedin ^= LF_POLY_ODD & s->odd;
    feedin ^= LF_POLY_EVEN & s->even;
    s->even = s->even << 1 | (evenparity32(feedin));

    t = s->odd;
    s->odd = s->even;
    s->even = t;

    return ret;
}
uint8_t crypto1_byte(struct Crypto1State *s, uint8_t in, int is_encrypted)
{
    uint8_t ret = 0;
    ret |= crypto1_bit(s, BIT(in, 0), is_encrypted) << 0;
    ret |= crypto1_bit(s, BIT(in, 1), is_encrypted) << 1;
    ret |= crypto1_bit(s, BIT(in, 2), is_encrypted) << 2;
    ret |= crypto1_bit(s, BIT(in, 3), is_encrypted) << 3;
    ret |= crypto1_bit(s, BIT(in, 4), is_encrypted) << 4;
    ret |= crypto1_bit(s, BIT(in, 5), is_encrypted) << 5;
    ret |= crypto1_bit(s, BIT(in, 6), is_encrypted) << 6;
    ret |= crypto1_bit(s, BIT(in, 7), is_encrypted) << 7;
    return ret;
}
uint32_t crypto1_word(struct Crypto1State *s, uint32_t in, int is_encrypted)
{
    uint32_t ret = 0;
    // note: xor args have been swapped because some compilers emit a warning
    // for 10^x and 2^x as possible misuses for exponentiation. No comment.
    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 0), is_encrypted) << (24 ^ 0);
    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 1), is_encrypted) << (24 ^ 1);
    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 2), is_encrypted) << (24 ^ 2);
    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 3), is_encrypted) << (24 ^ 3);
    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 4), is_encrypted) << (24 ^ 4);
    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 5), is_encrypted) << (24 ^ 5);
    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 6), is_encrypted) << (24 ^ 6);
    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 7), is_encrypted) << (24 ^ 7);

    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 8), is_encrypted) << (24 ^ 8);
    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 9), is_encrypted) << (24 ^ 9);
    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 10), is_encrypted) << (24 ^ 10);
    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 11), is_encrypted) << (24 ^ 11);
    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 12), is_encrypted) << (24 ^ 12);
    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 13), is_encrypted) << (24 ^ 13);
    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 14), is_encrypted) << (24 ^ 14);
    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 15), is_encrypted) << (24 ^ 15);

    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 16), is_encrypted) << (24 ^ 16);
    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 17), is_encrypted) << (24 ^ 17);
    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 18), is_encrypted) << (24 ^ 18);
    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 19), is_encrypted) << (24 ^ 19);
    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 20), is_encrypted) << (24 ^ 20);
    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 21), is_encrypted) << (24 ^ 21);
    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 22), is_encrypted) << (24 ^ 22);
    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 23), is_encrypted) << (24 ^ 23);

    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 24), is_encrypted) << (24 ^ 24);
    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 25), is_encrypted) << (24 ^ 25);
    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 26), is_encrypted) << (24 ^ 26);
    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 27), is_encrypted) << (24 ^ 27);
    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 28), is_encrypted) << (24 ^ 28);
    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 29), is_encrypted) << (24 ^ 29);
    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 30), is_encrypted) << (24 ^ 30);
    ret |= (uint32_t)crypto1_bit(s, BEBIT(in, 31), is_encrypted) << (24 ^ 31);
    return ret;
}

/* prng_successor
 * helper used to obscure the keystream during authentication
 */
uint32_t prng_successor(uint32_t x, uint32_t n)
{
    SWAPENDIAN(x);
    while (n--)
        x = x >> 1 | (x >> 16 ^ x >> 18 ^ x >> 19 ^ x >> 21) << 31;

    return SWAPENDIAN(x);
}
