// Linux test shim: fail every launch by default, or one in N launches with
// RECOVERY_TEST_FAIL_EVERY=N. LD_PRELOAD when checking recovery fallbacks.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <pthread.h>
#include <unistd.h>
#include <stdlib.h>

int pthread_create(pthread_t *thread, const pthread_attr_t *attr,
                   void *(*start)(void *), void *arg)
{
    static unsigned calls;
    const char *setting = getenv("RECOVERY_TEST_FAIL_EVERY");
    long every = setting ? strtol(setting, NULL, 10) : 1;
    if (every <= 1 || __atomic_fetch_add(&calls, 1, __ATOMIC_RELAXED) % (unsigned long)every == 0)
        return EAGAIN;
    int (*real_create)(pthread_t *, const pthread_attr_t *, void *(*)(void *), void *) =
        (int (*)(pthread_t *, const pthread_attr_t *, void *(*)(void *), void *))dlsym(RTLD_NEXT, "pthread_create");
    return real_create(thread, attr, start, arg);
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
