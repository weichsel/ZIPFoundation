/*
 *  funopen_compat.c
 *  ZIPFoundation
 *
 *  Copyright © 2017-2019 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
 *  Released under the MIT License.
 *
 *  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
 */

/* In case we need fopencookie */
#define _GNU_SOURCE 1
#include <funopen_compat.h>

#if EMULATE_FUNOPEN_WITH_FOPENCOOKIE
#include <stdlib.h>
#include <errno.h>
#include <unistd.h>

static ssize_t funopen_emulate_read(void *cookie, char *buf, size_t size);
static ssize_t funopen_emulate_write(void *cookie, const char *buf, size_t size);
static int     funopen_emulate_seek(void *cookie, off64_t *offset, int whence);
static int     funopen_emulate_close(void *cookie);

static cookie_io_functions_t emulation_funcs = {
    funopen_emulate_read, funopen_emulate_write, funopen_emulate_seek, funopen_emulate_close
};

typedef struct {
    void * orig_cookie;
    int (*orig_readfn)(void *, char *, int);
    int (*orig_writefn)(void *, const char *, int);
    long long (*orig_seekfn)(void *, long long, int);
    int (*orig_closefn)(void *);
} funopen_emulation_cookie;

FILE *
funopen(const void *cookie, int (*readfn)(void *, char *, int), int (*writefn)(void *, const char *, int),
        long long (*seekfn)(void *, long long, int), int (*closefn)(void *)) {
    funopen_emulation_cookie *emu_cookie = (funopen_emulation_cookie *)malloc(sizeof(funopen_emulation_cookie));
    if (!emu_cookie) {
        return NULL;
    }

    emu_cookie->orig_cookie  = (void *)cookie;
    emu_cookie->orig_readfn  = readfn;
    emu_cookie->orig_writefn = writefn;
    emu_cookie->orig_seekfn  = seekfn;
    emu_cookie->orig_closefn = closefn;

    const char *posix_mode   = readfn ? (writefn ? "rb+" : "rb") : "wb";

    return fopencookie(emu_cookie, posix_mode, emulation_funcs);
}

ssize_t
funopen_emulate_read(void *cookie, char *buf, size_t size) {
    int result = -1;
    funopen_emulation_cookie *emu_cookie = (funopen_emulation_cookie *)cookie;
    if (emu_cookie->orig_readfn) {
        result = emu_cookie->orig_readfn(emu_cookie->orig_cookie, buf, size);
    } else {
        errno = EINVAL;
    }
    return result;
}

ssize_t
funopen_emulate_write(void *cookie, const char *buf, size_t size) {
    int result = -1;
    funopen_emulation_cookie *emu_cookie = (funopen_emulation_cookie *)cookie;
    if (emu_cookie->orig_writefn) {
        result = emu_cookie->orig_writefn(emu_cookie->orig_cookie, buf, size);
    } else {
        errno = EINVAL;
    }
    return result;
}

int
funopen_emulate_seek(void *cookie, off64_t *offset, int whence) {
    int result = -1;
    funopen_emulation_cookie *emu_cookie = (funopen_emulation_cookie *)cookie;
    if (emu_cookie->orig_seekfn) {
        long long result_offset = emu_cookie->orig_seekfn(emu_cookie->orig_cookie, *offset, whence);
        if (result_offset >= 0) {
            *offset = result_offset;
            result  = 0;
        }
    } else {
        errno = EINVAL;
    }
    return result;
}

int
funopen_emulate_close(void *cookie) {
    int result = 0;
    funopen_emulation_cookie *emu_cookie = (funopen_emulation_cookie *)cookie;
    if (emu_cookie->orig_closefn) {
        result = emu_cookie->orig_closefn(emu_cookie->orig_cookie);
    }
    free(cookie);
    return result;
}

#elif EMULATE_FUNOPEN
#error "No method defined to emulate funopen"
#endif
