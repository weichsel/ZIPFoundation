/*
 *  funopen_compat.h
 *  ZIPFoundation
 *
 *  Copyright © 2017-2019 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
 *  Released under the MIT License.
 *
 *  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
 */

#ifndef FUNOPEN_COMPAT_H
#define FUNOPEN_COMPAT_H

#if defined(__linux__)
#define EMULATE_FUNOPEN
#define EMULATE_FUNOPEN_WITH_FOPENCOOKIE 1
#endif

#ifdef EMULATE_FUNOPEN
#include <stdio.h>

/* Note that seekfn uses long long instead of fpos_t. On BSD, fpos_t is an integer, on Linux it's not */
FILE *
funopen(const void *cookie, int (*readfn)(void *, char *, int), int (*writefn)(void *, const char *, int),
        long long (*seekfn)(void *, long long, int), int (*closefn)(void *));

#endif /* EMULATE_FUNOPEN */

#endif /* FUNOPEN_COMPAT_H */
