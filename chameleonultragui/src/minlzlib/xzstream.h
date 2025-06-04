/*++

Copyright (c) Alex Ionescu.  All rights reserved.

Module Name:

    xzstream.h

Abstract:

    This header file contains C-style data structures and enumerations that map
    back to the XZ stream and file format standard, including for the decoding
    of Variable Length Integers (VLI). This includes definitions for the stream
    header, block header, index and stream footer, and associated check types.

Author:

    Alex Ionescu (@aionescu) 15-Apr-2020 - Initial version

Environment:

    Windows & Linux, user mode and kernel mode.

--*/

#pragma once
#ifdef _MSC_VER
#pragma warning(disable : 4214)
#endif

#ifndef __XZ_STEAM_CONST
#define __XZ_STEAM_CONST

//
// This is the filter ID for LZMA2 as part of an XZ block header's "LzmaFlags"
//
static const uint8_t k_XzLzma2FilterIdentifier = 0x21;

//
// These are the magic bytes at the beginning of an XZ stream footer
//
static const uint16_t k_XzStreamFooterMagic = 23129; // 'ZY';

//
// These are the magic bytes at the beginning of an XZ stream header
//
static const uint8_t k_XzStreamHeaderMagic0 = 0xFD;
static const uint32_t k_XzStreamHeaderMagic1 = 1515747895; // 'ZXz7';
static const uint8_t k_XzStreamHeaderMagic5 = 0x00;

static const uint8_t k_XzBlockCheckSizes[] =
    {
        0, 4, 4, 4, 8, 8, 8, 16, 16, 16, 32, 32, 32, 64, 64, 64};

#endif

//
// XZ Blocks can be checksumed with algorithms of one of these possible sizes,
// based on the 4 bits indicated in the "CheckType" field of the stream header.
//

bool XzDecode(
    const uint8_t *InputBuffer,
    uint32_t InputSize,
    uint8_t *OutputBuffer,
    uint32_t *OutputSize);

//
// XZ streams encode certain numbers as "variable length integers", with 7 bits
// for the data, and a high bit to encode that another byte must be consumed.
//
typedef uint32_t vli_type;
#define VLI_BYTES_MAX (sizeof(vli_type) * 8 / 7)

//
// These are the possible supported types for integrity checking in an XZ file
//
typedef enum _XZ_CHECK_TYPES
{
    XzCheckTypeNone = 0,
    XzCheckTypeCrc32 = 1,
    XzCheckTypeCrc64 = 4,
    XzCheckTypeSha2 = 10
} XZ_CHECK_TYPES;

//
// This describes the first 12 bytes of any XZ container file / stream
//
typedef struct _XZ_STREAM_HEADER
{
    uint8_t Magic[6];

    union
    {
        struct
        {
            uint8_t ReservedFlags;
            uint8_t CheckType : 4;
            uint8_t ReservedType : 4;
        } s;

        uint16_t Flags;
    } u;

    uint32_t Crc32;
} XZ_STREAM_HEADER, *PXZ_STREAM_HEADER;

//
// This describes the last 12 bytes of any XZ container file / stream
//
typedef struct _XZ_STREAM_FOOTER
{
    uint32_t Crc32;
    uint32_t BackwardSize;

    union
    {
        struct
        {
            uint8_t ReservedFlags;
            uint8_t CheckType : 4;
            uint8_t ReservedType : 4;
        } s;

        uint16_t Flags;
    } u;

    uint16_t Magic;
} XZ_STREAM_FOOTER, *PXZ_STREAM_FOOTER;

//
// This describes the beginning of a compressed payload stored in an XZ stream,
// with hardcoded expectations for an LZMA2-compressed payload that has 0 extra
// filters (such as BCJ2).
//
typedef struct _XZ_BLOCK_HEADER
{
    uint8_t Size;

    union
    {
        struct
        {
            uint8_t FilterCount : 2;
            uint8_t Reserved : 4;
            uint8_t HasCompressedSize : 1;
            uint8_t HasUncompressedSize : 1;
        } s;

        uint8_t Flags;
    } u;

    struct
    {
        uint8_t Id;
        uint8_t Size;

        union
        {
            struct
            {
                uint8_t DictionarySize : 6;
                uint8_t Reserved : 2;
            } s;

            uint8_t Properties;
        } u;
    } LzmaFlags;

    uint8_t Padding[3];
    uint32_t Crc32;
} XZ_BLOCK_HEADER, *PXZ_BLOCK_HEADER;