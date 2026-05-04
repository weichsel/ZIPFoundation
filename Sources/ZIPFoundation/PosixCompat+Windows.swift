//
//  PosixCompat+Windows.swift
//  ZIPFoundation
//
//  Windows-only POSIX compatibility shims. ZIPFoundation's archive-mode
//  bookkeeping (file vs directory vs symlink) and timestamp arithmetic
//  use POSIX type names (`mode_t`, `S_IFLNK`, `timeval`, `suseconds_t`)
//  and functions (`fseeko`, `timegm`) that the MSVC-flavoured Swift
//  toolchain doesn't expose. The shims here let the same call sites
//  compile on Windows with no `#if os(Windows)` peppering at every use.
//
//  These shims match POSIX semantics only as far as ZIPFoundation needs
//  them — they're not a general-purpose POSIX-on-Windows port:
//
//    • Symlink-aware wrappers (`lchmod`, `lutimes`, `lstat`) are *not*
//      shimmed; the call sites that use them are already Apple-gated
//      via `#if os(macOS)…` so they never reach Windows.
//    • `S_IFLNK` is the POSIX bit pattern (`0o120000`); Windows has no
//      true equivalent (junctions / reparse points are different beasts),
//      but ZIPFoundation only writes / reads it through ZIP archive
//      external-file-attribute fields, so a numeric stand-in is enough.
//

#if os(Windows)

import Foundation
import WinSDK

public typealias mode_t = UInt16

// `<sys/stat.h>` POSIX file-mode bits — values match the Linux/Apple
// definitions so external-file-attribute round-trips with archives
// created on those platforms preserve the type bits exactly.
public let S_IFMT:  mode_t = 0o170000
public let S_IFREG: mode_t = 0o100000
public let S_IFDIR: mode_t = 0o040000
public let S_IFLNK: mode_t = 0o120000

// `suseconds_t` is the POSIX type for the microsecond field of `timeval`.
// On Windows the WinSock `timeval.tv_usec` is `LONG`, so a 32-bit signed
// integer matches binary-layout-wise.
public typealias suseconds_t = Int32

// Use the WinSock `timeval` struct under a POSIX-shaped alias so the
// call sites in `Date+ZIP.swift`/`FileManager+ZIP.swift` work unchanged.
public typealias POSIXTimeval = timeval

// `timegm(3)` — Windows ships the same conversion as `_mkgmtime`. Both
// take a calendar `tm` in UTC and produce a `time_t`.
@inlinable
public func timegm(_ tm: UnsafeMutablePointer<tm>) -> time_t {
    return _mkgmtime(tm)
}

// `fseeko(3)` with a 64-bit offset. Windows has `_fseeki64`. The
// shim takes `Int64` directly because WinSDK imports `off_t` as
// `Int32`, which would silently truncate ZIP offsets >2 GiB. Call
// sites cast via `zip_off_t` (defined below) so the same source
// expression works on every platform. The stream argument is an
// `OpaquePointer` because `FILE` imports as opaque from the MSVC SDK.
@inlinable
public func fseeko(_ stream: OpaquePointer, _ offset: Int64, _ whence: Int32) -> Int32 {
    return _fseeki64(stream, offset, whence)
}

// `ftruncate(2)` shim — Windows has `_chsize_s` (or `_chsize` for the
// 32-bit form). `_chsize_s` returns 0 on success, non-zero on failure;
// match POSIX's 0/-1 contract.
@inlinable
public func ftruncate(_ fd: Int32, _ length: Int64) -> Int32 {
    return _chsize_s(fd, length) == 0 ? 0 : -1
}

#endif

// Cross-platform "ZIP file offset" alias. Lets call sites write
// `fseeko(file, zip_off_t(offset), SEEK_SET)` once and have it expand
// to the right 64-bit signed integer on every host.
//
// `off_t` is provided by Darwin / Glibc / Bionic on those platforms;
// the explicit imports here keep this file standalone (no transitive
// reliance on `import Foundation` from elsewhere in the module).
#if os(Windows)
public typealias zip_off_t = Int64
#else
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#elseif canImport(Bionic)
import Bionic
#endif
public typealias zip_off_t = off_t
#endif
