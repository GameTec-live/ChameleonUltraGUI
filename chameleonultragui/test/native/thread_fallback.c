// Linux test shim: force the single-CPU path and every thread launch to fail.
// LD_PRELOAD this library when running recovery_check.py (without hardnested,
// whose upstream thread management does not support launch failures).
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <pthread.h>
#include <unistd.h>
#include <stdlib.h>

int pthread_create(pthread_t *thread, const pthread_attr_t *attr,
                   void *(*start)(void *), void *arg)
{
    (void)thread; (void)attr; (void)start; (void)arg;
    return EAGAIN;
}

long sysconf(int name)
{
    if (name == _SC_NPROCESSORS_ONLN) {
        const char *cpus = getenv("RECOVERY_TEST_CPUS");
        return cpus ? strtol(cpus, NULL, 10) : 1;
    }
    long (*real_sysconf)(int) = (long (*)(int))dlsym(RTLD_NEXT, "sysconf");
    return real_sysconf(name);
}
