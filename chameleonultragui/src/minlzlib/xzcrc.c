/*++

Copyright (c) Alex Ionescu.  All rights reserved.

Module Name:

    xzcrc.c

Abstract:

    This module implements the XZ checksum algorithms for CRC32 and CRC64. The
    latter is a specialized implementation (ofter mislabelled "ECMA-182") which
    is only available in Go, making it highly unlikely to be found in any other
    OS or language runtime. See the XZ Format Specification, Section 6.

Author:

    Alex Ionescu (@aionescu) 15-May-2021 - Initial version

Environment:

    Windows & Linux, user mode and kernel mode.

--*/

#include "minlzlib.h"

#ifdef MINLZ_INTEGRITY_CHECKS
const uint32_t k_Crc32Polynomial = UINT32_C(0xEDB88320);
const uint64_t k_Crc64Polynomial = UINT64_C(0xC96C5795D7870F42);

//
// XZ CRC State
//
typedef struct _CHECKSUM_STATE
{
    uint32_t Crc32Table[256];
    uint64_t Crc64Table[256];
    bool Initialized;
} CHECKSUM_STATE, * PCHECKSUM_STATE;
CHECKSUM_STATE Checksum;

void
XzCrcInitialize (
    void
    )
{
    uint32_t i;
    uint32_t j;
    uint32_t crc32;
    uint64_t crc64;

    //
    // Don't do anything if the tables are already computed
    //
    if (!Checksum.Initialized)
    {
        //
        // Build a table of all possible CRC values for each byte, essentially
        // creating the checksums for either 00 00 00 XX in the case of 32-bit
        // CRC or for 00 00 00 00 00 00 XX in the base of 64-bit CRC.
        //
        for (i = 0; i < 256; i++)
        {
            crc32 = i;
            crc64 = i;

            //
            // Divide the input in the 8 coefficients, where the LSB represents
            // the coefficient of the highest degree term of the dividend.
            //
            for (j = 0; j < 8; j++)
            {
                //
                // Is the current coefficient set?
                //
                if (crc32 & 1)
                {
                    //
                    // Move to next coefficient and add the rest of the divisor
                    //
                    crc32 = (crc32 >> 1) ^ k_Crc32Polynomial;
                }
                else
                {
                    //
                    // Skip this and move to the next coefficient
                    //
                    crc32 >>= 1;
                }

                //
                // Compute the 64-bit entry using the same algorithm
                //
                if (crc64 & 1)
                {
                    crc64 = (crc64 >> 1) ^ k_Crc64Polynomial;
                }
                else
                {
                    crc64 >>= 1;
                }
            }

            //
            // Store the final generated result
            //
            Checksum.Crc32Table[i] = crc32;
            Checksum.Crc64Table[i] = crc64;
        }

        //
        // No need to do this again
        //
        Checksum.Initialized = true;
    }
}

uint32_t
XzCrc32 (
    uint32_t Crc,
    const uint8_t *Buffer,
    uint32_t Length
    )
{
    uint32_t i;

    //
    // This uses the Dilip V. Sarwate algorithm which shifts one byte at a time
    // and produces an intermediate remainder which can then be subtracted from
    // the lookup table by using the high 8 bits as an index (since we computed
    // all possible one-byte inputs). This relies on the following property:
    //
    // Mod(A * x^n, P(x)) = Mod(x^n * Mod(A, P(X)), P(X))
    //
    for (XzCrcInitialize(), Crc = ~Crc, i = 0; i < Length; ++i)
    {
        Crc = Checksum.Crc32Table[Buffer[i] ^ (Crc & 0xFF)] ^ (Crc >> 8);
    }
    return ~Crc;
}

uint64_t
XzCrc64 (
    uint64_t Crc,
    const uint8_t *Buffer,
    uint32_t Length
    )
{
    uint32_t i;
    //
    // Use the same algorithm to the 64-bit case too. Note that for very large
    // input data, a parallel "slicing by 8" approach would yield much faster
    // results (as would a "slicing by 4" approach for the 32-bit CRC case).
    //
    for (XzCrcInitialize(), Crc = ~Crc, i = 0; i < Length; ++i)
    {
        Crc = Checksum.Crc64Table[Buffer[i] ^ (Crc & 0xFF)] ^ (Crc >> 8);
    }
    return ~Crc;
}
#endif
