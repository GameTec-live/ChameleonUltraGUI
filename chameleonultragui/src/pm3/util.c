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
// utilities
//-----------------------------------------------------------------------------

#if defined(__linux__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif
#include "util.h"

// global client debug variable
uint8_t g_debugMode = 0;
// global client disable logging variable
uint8_t g_printAndLog = PRINTANDLOG_PRINT | PRINTANDLOG_LOG;
// global client tell if a pending prompt is present

#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h>
#if defined(__linux__)
#include <sched.h>
#endif
#endif

// determine number of logical CPU cores (use for multithreaded functions)
int num_CPUs(void)
{
#if defined(_WIN32)
#include <sysinfoapi.h>
    SYSTEM_INFO sysinfo;
    GetSystemInfo(&sysinfo);
    return sysinfo.dwNumberOfProcessors;
#else
    int count = sysconf(_SC_NPROCESSORS_ONLN);
#if defined(__linux__)
    // Android cpusets and desktop affinity can expose fewer CPUs than sysconf.
    cpu_set_t available;
    if (sched_getaffinity(0, sizeof(available), &available) == 0)
        count = CPU_COUNT(&available);
#endif
    if (count <= 0)
        count = 1;
    return count;
#endif
}
