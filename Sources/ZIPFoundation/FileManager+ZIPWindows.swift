//
//  FileManager+ZIPWindows.swift
//  ZIPFoundation
//
//  Windows-only fallbacks for the metadata helpers in `FileManager+ZIP.swift`.
//  The POSIX implementations there go through `lstat()` / `stat()` and read
//  microsecond-resolution timestamps that Windows does not expose. Each
//  method here matches the signature of its POSIX sibling so call sites
//  stay platform-agnostic.
//

#if os(Windows)

import Foundation

extension FileManager {

    class func permissionsForItem(at URL: URL) throws -> UInt16 {
        var isDir: ObjCBool = false
        let exists = FileManager().fileExists(atPath: URL.path, isDirectory: &isDir)
        guard exists else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: URL.path])
        }
        return isDir.boolValue ? defaultDirectoryPermissions : defaultFilePermissions
    }

    class func fileModificationDateTimeForItem(at url: URL) throws -> Date {
        let fileManager = FileManager()
        guard fileManager.itemExists(at: url) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        // `attributesOfItem` reads the same Win32 file metadata as `_stat64`
        // but doesn't expose nanosecond precision — fine here since ZIP's
        // MS-DOS time format is two-second-granular anyway.
        let attrs = try fileManager.attributesOfItem(atPath: url.path)
        return (attrs[.modificationDate] as? Date) ?? Date()
    }

    class func fileSizeForItem(at url: URL) throws -> Int64 {
        let fileManager = FileManager()
        guard fileManager.itemExists(at: url) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        let attrs = try fileManager.attributesOfItem(atPath: url.path)
        guard let size = attrs[.size] as? NSNumber else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        return size.int64Value
    }

    class func typeForItem(at url: URL) throws -> Entry.EntryType {
        let fileManager = FileManager()
        guard url.isFileURL, fileManager.itemExists(at: url) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        // Windows has no `lstat`, and reparse-point detection isn't worth
        // the Win32 dance for our archive use case. Distinguish file vs
        // directory via FileManager; symlinks fall back to .file.
        var isDir: ObjCBool = false
        _ = fileManager.fileExists(atPath: url.path, isDirectory: &isDir)
        return isDir.boolValue ? .directory : .file
    }
}

#endif
