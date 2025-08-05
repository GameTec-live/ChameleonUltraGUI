#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#if _WIN32
#include <windows.h>
#else
#include <pthread.h>
#include <unistd.h>
#endif

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT
#endif

typedef struct
{
    uint32_t nt1;
    uint64_t ks1;
    uint64_t par;
    uint32_t nr;
    uint32_t ar;
} DarksideItem;

typedef struct
{
    uint32_t uid;
    DarksideItem *items;
    uint32_t count;
} Darkside;

typedef struct
{
    uint32_t uid;
    uint32_t dist;
    uint32_t nt0;
    uint32_t nt0_enc;
    uint32_t par0;
    uint32_t nt1;
    uint32_t nt1_enc;
    uint32_t par1;
} Nested;

typedef struct
{
    uint32_t uid;
    uint32_t key_type;
    uint32_t nt0;
    uint32_t nt0_enc;
    uint32_t nt1;
    uint32_t nt1_enc;
} StaticNested;

typedef struct
{
    uint32_t uid;
    uint32_t nt;
    uint32_t nt_enc;
    uint32_t nt_par_enc;
} StaticEncryptedNested;

typedef struct
{
    uint32_t uid;     // serial number
    uint32_t nt0;     // tag challenge first
    uint32_t nt1;     // tag challenge second
    uint32_t nr0_enc; // first encrypted reader challenge
    uint32_t ar0_enc; // first encrypted reader response
    uint32_t nr1_enc; // second encrypted reader challenge
    uint32_t ar1_enc; // second encrypted reader response
} Mfkey32;

typedef struct
{
    char *nonces;
    uint32_t length;
} HardNested;

FFI_PLUGIN_EXPORT uint64_t *darkside(Darkside *data, uint32_t *keyCount);

FFI_PLUGIN_EXPORT uint64_t *nested(Nested *data, uint32_t *keyCount);

FFI_PLUGIN_EXPORT uint64_t *static_nested(StaticNested *data, uint32_t *keyCount);

FFI_PLUGIN_EXPORT uint64_t *static_encrypted_nested(StaticEncryptedNested *data, uint32_t *keyCount);

FFI_PLUGIN_EXPORT uint64_t mfkey32(Mfkey32 *data);

FFI_PLUGIN_EXPORT uint64_t hardnested(HardNested *data);