#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <ctype.h>

#include "parity.h"
#include "crapto1.h"
#include "mfkey.h"
#include "recovery.h"

#if WIN32
#include "windows.h"
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#else
#include "unistd.h"
#include <sys/param.h>
#endif

#include "hardnested.h"

#define MEM_CHUNK 10000
#define TRY_KEYS 50

typedef struct
{
  uint32_t nt;
  uint32_t nr;
  uint32_t ar;

  uint64_t par_list;
  uint64_t ks_list;
} DarksideParam;

typedef struct
{
  uint32_t ntp;
  uint32_t ks1;
} NtpKs1;

typedef struct
{
  NtpKs1 *pNK;
  uint32_t authuid;

  uint64_t *keys;
  uint32_t keyCount;

  uint32_t startPos;
  uint32_t endPos;
} RecPar;

FFI_PLUGIN_EXPORT uint64_t hardnested(HardNested *data)
{
  uint64_t foundkey = 0;
  mfnestedhard(0, 0, NULL, 0, 0, NULL, false, false, false, &foundkey, data->nonces, data->length);
  return foundkey;
}

FFI_PLUGIN_EXPORT uint64_t *darkside(Darkside *data, uint64_t *outputKeyCount)
{
  uint32_t uid = data->uid;
  uint32_t count = 0, i = 0;
  uint64_t keycount = 0;
  uint64_t *keylist = NULL, *last_keylist = NULL;
  DarksideParam *dps = calloc(1, sizeof(DarksideParam) * data->count);
  uint64_t *keys = malloc(sizeof(uint64_t) * 256);
  bool no_key_recover = true;

  for (count = 0; count < data->count; count++)
  {
    dps[count].nt = data->items[count].nt1;
    dps[count].ks_list = data->items[count].ks1;
    dps[count].par_list = data->items[count].par;
    dps[count].nr = data->items[count].nr;
    dps[count].ar = data->items[count].ar;
  }

  for (i = 0; i < count && *outputKeyCount == 0; i++)
  {
    uint32_t nt = dps[i].nt;
    uint32_t nr = dps[i].nr;
    uint32_t ar = dps[i].ar;
    uint64_t par_list = dps[i].par_list;
    uint64_t ks_list = dps[i].ks_list;

    keycount = nonce2key(uid, nt, nr, ar, par_list, ks_list, &keylist);

    if (keycount == 0)
    {
      continue;
    }

    // only parity zero attack
    if (par_list == 0)
    {
      qsort(keylist, keycount, sizeof(*keylist), compare_uint64);
      keycount = intersection(last_keylist, keylist);
      if (keycount == 0)
      {
        free(last_keylist);
        last_keylist = keylist;
        continue;
      }
    }

    if (keycount > 0)
    {
      no_key_recover = false;
      *outputKeyCount = MIN(256, keycount);
      for (i = 0; i < *outputKeyCount; i++)
      {
        if (par_list == 0)
        {
          keys[i] = last_keylist[i];
        }
        else
        {
          keys[i] = keylist[i];
        }
      }

      return keys;
    }

    if (last_keylist == keylist && last_keylist != NULL)
    {
      free(keylist);
    }
    else
    {
      if (last_keylist)
      {
        free(last_keylist);
      }
      if (keylist)
      {
        free(keylist);
      }
    }
    free(dps);
  }

  return malloc(1);
}

int uint64_compare(const void *a, const void *b)
{
  return (*(uint64_t *)a > *(uint64_t *)b) - (*(uint64_t *)a < *(uint64_t *)b);
}

uint64_t *most_frequent_uint64(uint64_t *keys, uint32_t size, uint32_t *outputKeyCount)
{
  uint64_t i, maxFreq = 1, currentFreq = 1, currentItem = keys[0];
  uint64_t *output = calloc(size, sizeof(uint64_t));
  qsort(keys, size, sizeof(uint64_t), uint64_compare);

  for (i = 1; i < size; i++)
  {
    if (keys[i] == keys[i - 1])
    {
      currentFreq++;
    }
    else
    {
      if (currentFreq > maxFreq)
      {
        maxFreq = currentFreq;
      }
      currentFreq = 1;
    }
  }
  if (currentFreq > maxFreq)
  {
    maxFreq = currentFreq;
  }

  currentItem = keys[0];
  currentFreq = 1;
  for (i = 1; i <= size; i++)
  {
    if (i < size && keys[i] == keys[i - 1])
    {
      currentFreq++;
    }
    else
    {
      if (currentFreq == maxFreq)
      {
        output[*outputKeyCount] = currentItem;
        *outputKeyCount += 1;
      }
      if (i < size)
      {
        currentItem = keys[i];
        currentFreq = 1;
      }
    }
  }

  return output;
}

// nested decrypt
static void nested_recover(RecPar *rp)
{
  struct Crypto1State *revstate, *revstate_start = NULL;
  uint64_t lfsr = 0;
  uint32_t i, kcount = 0;

  rp->keyCount = 0;
  rp->keys = NULL;

  for (i = rp->startPos; i < rp->endPos; i++)
  {
    uint32_t nt_probe = rp->pNK[i].ntp;
    uint32_t ks1 = rp->pNK[i].ks1;
    // And finally recover the first 32 bits of the key
    revstate = lfsr_recovery32(ks1, nt_probe ^ rp->authuid);
    if (revstate_start == NULL)
    {
      revstate_start = revstate;
    }
    while ((revstate->odd != 0x0) || (revstate->even != 0x0))
    {
      lfsr_rollback_word(revstate, nt_probe ^ rp->authuid, 0);
      crypto1_get_lfsr(revstate, &lfsr);
      // Allocate a new space for keys
      if (((kcount % MEM_CHUNK) == 0) || (kcount >= rp->keyCount))
      {
        rp->keyCount += MEM_CHUNK;
        // printf("New chunk by %d, sizeof %lu\n", kcount, key_count * sizeof(uint64_t));
        void *tmp = realloc(rp->keys, rp->keyCount * sizeof(uint64_t));
        if (tmp == NULL)
        {
          printf("Memory allocation error for pk->possibleKeys");
          // exit(EXIT_FAILURE);
          rp->keyCount = 0;
          return;
        }
        rp->keys = (uint64_t *)tmp;
      }
      rp->keys[kcount] = lfsr;
      kcount++;
      revstate++;
    }
    free(revstate_start);
    revstate_start = NULL;
  }
  // Truncate
  if (kcount != 0)
  {
    rp->keyCount = --kcount;
    void *tmp = (uint64_t *)realloc(rp->keys, rp->keyCount * sizeof(uint64_t));
    if (tmp == NULL)
    {
      printf("Memory allocation error for pk->possibleKeys");
      // exit(EXIT_FAILURE);
      rp->keyCount = 0;
      return;
    }
    rp->keys = tmp;
    return;
  }
  rp->keyCount = 0;
  return;
}

uint64_t *nested_run(NtpKs1 *pNK, uint32_t sizePNK, uint32_t authuid, uint32_t *keyCount, uint32_t *outputKeyCount)
{
  *keyCount = 0;
  *outputKeyCount = 0;

  RecPar *pRPs = malloc(sizeof(RecPar));
  if (pRPs == NULL)
  {
    return NULL;
  }

  pRPs->pNK = pNK;
  pRPs->authuid = authuid;
  pRPs->startPos = 0;
  pRPs->endPos = sizePNK;

  // start recover
  nested_recover(pRPs);
  *keyCount = pRPs->keyCount;

  uint64_t *keys = NULL;
  if (*keyCount != 0)
  {
    keys = malloc(*keyCount * sizeof(uint64_t));
    if (keys != NULL)
    {
      memcpy(keys, pRPs->keys, pRPs->keyCount * sizeof(uint64_t));
      free(pRPs->keys);
      keys = most_frequent_uint64(keys, *keyCount, outputKeyCount);
    }
  }
  free(pRPs);

  return keys;
}

// Return 1 if the nonce is invalid else return 0
static uint8_t valid_nonce(uint32_t Nt, uint32_t NtEnc, uint32_t Ks1, uint8_t *parity)
{
  return (
             (oddparity8((Nt >> 24) & 0xFF) == ((parity[0]) ^ oddparity8((NtEnc >> 24) & 0xFF) ^ BIT(Ks1, 16))) &&
             (oddparity8((Nt >> 16) & 0xFF) == ((parity[1]) ^ oddparity8((NtEnc >> 16) & 0xFF) ^ BIT(Ks1, 8))) &&
             (oddparity8((Nt >> 8) & 0xFF) == ((parity[2]) ^ oddparity8((NtEnc >> 8) & 0xFF) ^ BIT(Ks1, 0))))
             ? 1
             : 0;
}

FFI_PLUGIN_EXPORT uint64_t *nested(Nested *data, uint32_t *outputKeyCount)
{
  NtpKs1 *pNK = NULL;
  uint32_t i, j = 0, m;
  uint32_t nt1, nt2, nttest, ks1;
  uint8_t par_int;
  uint8_t par_arr[3] = {0x00};

  uint32_t authuid = data->uid;
  uint32_t dist = data->dist;

  // process all args.
  for (i = 0; i < 2; i++)
  {
    if (i == 0)
    {
      nt1 = data->nt0;
      nt2 = data->nt0_enc;
      par_int = data->par0;
    }
    else
    {
      nt1 = data->nt1;
      nt2 = data->nt1_enc;
      par_int = data->par1;
    }

    for (m = 0; m < 3; m++)
    {
      par_arr[m] = (par_int >> m) & 0x01;
    }
    // Try to recover the keystream1
    nttest = prng_successor(nt1, dist - 14);
    for (m = dist - 14; m <= dist + 14; m += 1)
    {
      ks1 = nt2 ^ nttest;
      if (valid_nonce(nttest, nt2, ks1, par_arr))
      {
        ++j;
        // append to list
        void *tmp = realloc(pNK, sizeof(NtpKs1) * j);
        pNK = tmp;
        pNK[j - 1].ntp = nttest;
        pNK[j - 1].ks1 = ks1;
      }
      nttest = prng_successor(nttest, 1);
    }
  }

  uint32_t keyCount = 0;
  uint64_t *keys = nested_run(pNK, j, authuid, &keyCount, outputKeyCount);
  *outputKeyCount = MIN(256, *outputKeyCount);
  return keys;
}

FFI_PLUGIN_EXPORT uint64_t *static_nested(StaticNested *data, uint32_t *outputKeyCount)
{
  NtpKs1 *pNK = NULL;
  uint32_t i;
  uint32_t j = 0;
  uint32_t nt1, nt2, nttest, ks1, dist = 0;

  uint32_t authuid = data->uid;
  uint8_t type = (uint8_t)data->key_type; // target key type
  // process all args.
  bool check_st_level_at_first_run = false;
  for (i = 0; i < 2; i++)
  {
    if (i == 0)
    {
      nt1 = data->nt0;
      nt2 = data->nt0_enc;
    }
    else
    {
      nt1 = data->nt1;
      nt2 = data->nt1_enc;
    }

    if (!check_st_level_at_first_run)
    {
      if (nt1 == 0x01200145)
      {
        // There is no loophole in this generation.
        // This tag can be decrypted with the default parameter value 160!
        dist = 160; // st gen1
      }
      else if (nt1 == 0x009080A2)
      { // st gen2
        // We found that the gen2 tag is vulnerable too but parameter must be adapted depending on the attacked key
        if (type == 0x61)
        {
          dist = 161;
        }
        else if (type == 0x60)
        {
          dist = 160;
        }
        else
        {
          return NULL;
        }
      }
      else
      {
        return NULL;
      }
      check_st_level_at_first_run = true;
    }

    nttest = prng_successor(nt1, dist);
    ks1 = nt2 ^ nttest;
    ++j;
    dist += 160;

    void *tmp = realloc(pNK, sizeof(NtpKs1) * j);
    if (tmp == NULL)
    {
      return NULL;
    }

    pNK = tmp;
    pNK[j - 1].ntp = nttest;
    pNK[j - 1].ks1 = ks1;
  }

  uint32_t keyCount = 0;
  uint64_t *keys = nested_run(pNK, j, authuid, &keyCount, outputKeyCount);
  *outputKeyCount = MIN(256, *outputKeyCount);
  return keys;
}

FFI_PLUGIN_EXPORT uint64_t mfkey32(Mfkey32 *data)
{
  struct Crypto1State *s, *t;
  uint64_t key; // recovered key
  uint64_t ks2;

  // Generate lfsr successors of the tag challenge
  uint32_t p64 = prng_successor(data->nt0, 64);
  uint32_t p64b = prng_successor(data->nt1, 64);

  ks2 = data->ar0_enc ^ p64;

  s = lfsr_recovery32(data->ar0_enc ^ p64, 0);

  for (t = s; t->odd | t->even; ++t)
  {
    lfsr_rollback_word(t, 0, 0);
    lfsr_rollback_word(t, data->nr0_enc, 1);
    lfsr_rollback_word(t, data->uid ^ data->nt0, 0);
    crypto1_get_lfsr(t, &key);

    crypto1_word(t, data->uid ^ data->nt1, 0);
    crypto1_word(t, data->nr1_enc, 1);
    if (data->ar1_enc == (crypto1_word(t, 0, 0) ^ p64b))
    {
      free(s);
      return key;
    }
  }

  free(s);
  return UINT64_MAX;
}
