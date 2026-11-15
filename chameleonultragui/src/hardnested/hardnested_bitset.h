// SPDX-License-Identifier: GPL-3.0-or-later
// Inspired by ChameLab's HardnestedBitSet; see test/native/README.md.
// Internal immutable bitmap pages. Equal pages share storage; hash collisions
// always compare all words. Pools are built by one worker and then read-only.
#ifndef HARDNESTED_BITSET_H
#define HARDNESTED_BITSET_H
#define HARDNESTED_COMPACT_STATES 1

#define STATE_PAGE_WORDS 64u
#define STATE_PAGE_COUNT ((1u << 19) / STATE_PAGE_WORDS)
#define STATE_CHUNK_PAGES 1024u

static inline uint32_t state_count_word(uint32_t x)
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

typedef struct {
    uint64_t hash;
    uint32_t page;
} state_page_slot_t;

typedef struct {
    uint32_t **chunks;
    uint32_t count;
    size_t capacity;
    state_page_slot_t *slots;
} state_page_pool_t;

typedef struct {
    const uint32_t **pages;
} state_bitset_t;

static void *state_alloc(size_t size)
{
    void *result = calloc(1, size);
    if (!result) {
        PrintAndLogEx("Out of memory allocating compact states. Aborting...\n");
        exit(4);
    }
    return result;
}

static inline const uint32_t *state_page(const state_page_pool_t *pool, uint32_t page)
{
    return pool->chunks[page / STATE_CHUNK_PAGES] + (page % STATE_CHUNK_PAGES) * STATE_PAGE_WORDS;
}

static void state_pool_rehash(state_page_pool_t *pool, size_t capacity)
{
    state_page_slot_t *slots = state_alloc(capacity * sizeof(*slots));
    for (size_t i = 0; i < pool->capacity; ++i) {
        state_page_slot_t entry = pool->slots[i];
        if (!entry.page) continue;
        size_t at = entry.hash & (capacity - 1);
        while (slots[at].page) at = (at + 1) & (capacity - 1);
        slots[at] = entry;
    }
    free(pool->slots);
    pool->slots = slots;
    pool->capacity = capacity;
}

// Independent products allow SIMD hashing. Fixed odd weights distinguish word
// positions; the final mixing spreads high bits across the hash-table index.
HN_SIMD
static uint64_t state_page_hash(const uint32_t *words)
{
    static const uint32_t weights[STATE_PAGE_WORDS] = {
        0xeddf0483u, 0xa4a326a5u, 0xce8f157fu, 0xa83c8e8fu, 0x04433d59u, 0x1eedb90du, 0x9045f08bu, 0xe4c47381u,
        0x3c38bdbbu, 0x5a76c7fdu, 0xd3a9d1b9u, 0xda4a0b97u, 0xfc2c676bu, 0x68e6de6bu, 0xd657183fu, 0x9f489057u,
        0x2500c817u, 0xbc44f4d7u, 0x791a9299u, 0x427d409du, 0xa7bc20ebu, 0x578f567bu, 0x1549539bu, 0xd87b8ce7u,
        0x95003a95u, 0xd80c841du, 0x596f0b1bu, 0xb98ef49du, 0x84b5a553u, 0x33e056fdu, 0x1ec2a623u, 0x0adea701u,
        0x19e3ebdfu, 0xf79b2bd3u, 0xcec576e3u, 0x6339db2fu, 0x53dad701u, 0x2e60a03du, 0x7684bccfu, 0xc2bc8441u,
        0x14a1061bu, 0xb829d94bu, 0xe31fe1abu, 0xfa7b49ffu, 0xfbdccbddu, 0x36482b6fu, 0x579f8d5du, 0x60bbb6a7u,
        0xdb84ef91u, 0x88af59cbu, 0x11570801u, 0xfab9754bu, 0x561f9723u, 0x3b8f0e9fu, 0x91c8d5b1u, 0xe4ac91efu,
        0xa4b81e47u, 0x4965121fu, 0x8ff6760du, 0x67cd0477u, 0x2f337d17u, 0x52a2369fu, 0x9a4e6867u, 0xbf12fb27u,
    };
    uint64_t hash = 0;
    for (unsigned i = 0; i < STATE_PAGE_WORDS; ++i)
        hash += (uint64_t)words[i] * weights[i];
    hash ^= hash >> 33;
    hash *= UINT64_C(0xff51afd7ed558ccd);
    hash ^= hash >> 33;
    hash *= UINT64_C(0xc4ceb9fe1a85ec53);
    return hash ^ (hash >> 33);
}

HN_SIMD
static uint32_t state_pool_intern(state_page_pool_t *pool, const uint32_t *words)
{
    uint32_t any = 0;
    for (unsigned i = 0; i < STATE_PAGE_WORDS; ++i) any |= words[i];
    if (!pool->count) {
        pool->chunks = state_alloc(sizeof(*pool->chunks));
        pool->chunks[0] = state_alloc(STATE_CHUNK_PAGES * STATE_PAGE_WORDS * sizeof(uint32_t));
        pool->count = 1; // Page zero represents every empty page.
    }
    if (!any) return 0;
    uint64_t hash = state_page_hash(words);
    if (pool->count * 2 >= pool->capacity)
        state_pool_rehash(pool, pool->capacity ? pool->capacity * 2 : 1024);
    size_t at = hash & (pool->capacity - 1);
    while (pool->slots[at].page) {
        state_page_slot_t entry = pool->slots[at];
        if (entry.hash == hash && !memcmp(state_page(pool, entry.page), words, STATE_PAGE_WORDS * sizeof(uint32_t)))
            return entry.page;
        at = (at + 1) & (pool->capacity - 1);
    }
    uint32_t page = pool->count++;
    if (!(page % STATE_CHUNK_PAGES)) {
        size_t chunks = page / STATE_CHUNK_PAGES + 1;
        uint32_t **grown = realloc(pool->chunks, chunks * sizeof(*grown));
        if (!grown) { PrintAndLogEx("Out of memory growing compact states. Aborting...\n"); exit(4); }
        pool->chunks = grown;
        pool->chunks[chunks - 1] = state_alloc(STATE_CHUNK_PAGES * STATE_PAGE_WORDS * sizeof(uint32_t));
    }
    memcpy((uint32_t *)state_page(pool, page), words, STATE_PAGE_WORDS * sizeof(uint32_t));
    pool->slots[at] = (state_page_slot_t){hash, page};
    return page;
}

static state_bitset_t state_bitset_build(state_page_pool_t *pool, const uint32_t *words)
{
    state_bitset_t bits = {state_alloc(STATE_PAGE_COUNT * sizeof(*bits.pages))};
    for (unsigned page = 0; page < STATE_PAGE_COUNT; ++page)
        bits.pages[page] = state_page(pool, state_pool_intern(pool, words + page * STATE_PAGE_WORDS));
    return bits;
}

static inline uint32_t state_bitset_word(const state_bitset_t *bits, uint32_t index)
{
    return bits->pages[index / STATE_PAGE_WORDS][index % STATE_PAGE_WORDS];
}

static void state_pool_freeze(state_page_pool_t *pool)
{
    free(pool->slots);
    pool->slots = NULL;
    pool->capacity = 0;
}

static void state_pool_free(state_page_pool_t *pool)
{
    for (uint32_t i = 0; i < (pool->count + STATE_CHUNK_PAGES - 1) / STATE_CHUNK_PAGES; ++i)
        free(pool->chunks[i]);
    free(pool->chunks);
    free(pool->slots);
    memset(pool, 0, sizeof(*pool));
}

#endif
