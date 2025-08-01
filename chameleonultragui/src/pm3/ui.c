//-----------------------------------------------------------------------------
// Copyright (C) Proxmark3 contributors. See AUTHORS.md for details.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// See LICENSE.txt for the text of the license.
//-----------------------------------------------------------------------------
// UI utilities
//-----------------------------------------------------------------------------

/* Ensure strtok_r is available even with -std=c99; must be included before
 */

#include "ui.h"
#include "commonutil.h" // ARRAYLEN
#include <stdio.h>      // for Mingw readline
#include <stdarg.h>
#include <stdlib.h>

#include "util.h"

#include <string.h>

void PrintAndLogEx(const char *fmt, ...)
{
    char buffer[2048] = {0};

    va_list args;
    va_start(args, fmt);
    vsnprintf(buffer, sizeof(buffer), fmt, args);
    va_end(args);
    printf("%s\n", buffer);
}
