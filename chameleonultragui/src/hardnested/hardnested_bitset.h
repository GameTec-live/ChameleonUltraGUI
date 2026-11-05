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
    uint64_t hash = UINT64_C(14695981039346656037);
    for (unsigned i = 0; i < STATE_PAGE_WORDS; ++i)
        hash = (hash ^ words[i]) * UINT64_C(1099511628211);
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
