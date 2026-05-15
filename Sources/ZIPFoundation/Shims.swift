//
//  Shims.swift
//  ZIPFoundation
//
//  Copyright © 2017-2026 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
//

//  POSIX compatibility shims plus the cross-platform `zip_off_t` alias.
//  The Windows-only block below lets ZIPFoundation's archive-mode
//  bookkeeping (file vs directory vs symlink) and timestamp arithmetic
//  use POSIX type names (`mode_t`, `S_IFLNK`, `timeval`, `suseconds_t`)
//  and functions (`fseeko`, `timegm`) that the MSVC-flavoured Swift
//  toolchain doesn't expose — without `#if os(Windows)` peppering at
//  every call site. The tail of the file then defines `zip_off_t` on
//  every platform so seek/truncate offsets stay 64-bit-correct.
//
//  These shims match POSIX semantics only as far as ZIPFoundation needs
//  them — they're not a general-purpose POSIX-on-Windows port:
//
//  - Symlink-aware wrappers (`lchmod`, `lutimes`, `lstat`) are *not*
//    shimmed; the call sites that use them are already Apple-gated
//    via `#if os(macOS)…` so they never reach Windows.
//  - `S_IFLNK` is the POSIX bit pattern (`0o120000`); Windows has no
//    true equivalent (junctions / reparse points are different beasts),
//    but ZIPFoundation only writes / reads it through ZIP archive
//    external-file-attribute fields, so a numeric stand-in is enough.
//
//  The aliases below intentionally match POSIX names (`mode_t`, `S_IFMT`,
//  `timegm`, …) so call sites read identically across platforms — the
//  SwiftLint identifier/type-name rules are disabled here for that reason.
//
// swiftlint:disable identifier_name type_name

#if os(Windows)

import Foundation
import WinSDK

typealias mode_t = UInt16

// `<sys/stat.h>` POSIX file-mode bits — values match the Linux/Apple
// definitions so external-file-attribute round-trips with archives
// created on those platforms preserve the type bits exactly.
let S_IFMT: mode_t = 0o170000
let S_IFREG: mode_t = 0o100000
let S_IFDIR: mode_t = 0o040000
let S_IFLNK: mode_t = 0o120000

// `suseconds_t` is the POSIX type for the microsecond field of `timeval`.
// On Windows the WinSock `timeval.tv_usec` is `LONG`, so a 32-bit signed
// integer matches binary-layout-wise.
typealias suseconds_t = Int32

// `timegm(3)` — Windows ships the same conversion as `_mkgmtime`. Both
// take a calendar `tm` in UTC and produce a `time_t`.
func timegm(_ time: UnsafeMutablePointer<tm>) -> time_t {
    return _mkgmtime(time)
}

// `fseeko(3)` with a 64-bit offset. Windows has `_fseeki64`. The
// shim takes `Int64` directly because WinSDK imports `off_t` as
// `Int32`, which would silently truncate ZIP offsets >2 GiB. Call
// sites cast via `zip_off_t` (defined below) so the same source
// expression works on every platform. `FILE` is `_iobuf` on MSVC,
// imported as a typed struct, so we use `UnsafeMutablePointer<FILE>`
// here to match `_fseeki64`'s declared signature.
func fseeko(_ stream: UnsafeMutablePointer<FILE>, _ offset: Int64, _ whence: Int32) -> Int32 {
    return _fseeki64(stream, offset, whence)
}

// `ftello(3)` companion to `fseeko` — returns the current 64-bit
// stream offset. Maps to `_ftelli64` on Windows. Call sites already
// wrap the result in `Int64(ftello(...))` so a 64-bit return type
// works without further changes.
func ftello(_ stream: UnsafeMutablePointer<FILE>) -> Int64 {
    return _ftelli64(stream)
}

// `ftruncate(2)` shim — Windows has `_chsize_s` (or `_chsize` for the
// 32-bit form). `_chsize_s` returns 0 on success, non-zero on failure;
// match POSIX's 0/-1 contract.
func ftruncate(_ descriptor: Int32, _ length: Int64) -> Int32 {
    return _chsize_s(descriptor, length) == 0 ? 0 : -1
}

#endif

// Cross-platform "ZIP file offset" alias. Lets call sites write
// `fseeko(file, zip_off_t(offset), SEEK_SET)` once and have it expand
// to the right 64-bit signed integer on every host.
//
// `off_t` is provided by Darwin / Glibc / Musl / Android on those
// platforms; the explicit imports here keep this file standalone (no
// transitive reliance on `import Foundation` from elsewhere in the
// module).
#if os(Windows)
typealias zip_off_t = Int64
#else
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#else
#error("Unsupported platform: ZIPFoundation needs a C library that exposes off_t.")
#endif
typealias zip_off_t = off_t
#endif
// swiftlint:enable identifier_name type_name
