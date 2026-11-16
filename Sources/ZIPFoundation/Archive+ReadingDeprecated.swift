//
//  Archive+ReadingDeprecated.swift
//  ZIPFoundation
//
//  Copyright © 2017-2026 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/main/LICENSE for license information.
//

import Foundation

public extension Archive {

    @available(*, deprecated,
                message: "Please use `Int` for `bufferSize`.")
    func extract(_ entry: Entry, to url: URL, bufferSize: UInt32, skipCRC32: Bool = false,
                 progress: Progress? = nil) throws -> CRC32 {
        try self.extract(entry, to: url, bufferSize: Int(bufferSize), skipCRC32: skipCRC32, progress: progress)
    }

    @available(*, deprecated,
                message: "Please use `Int` for `bufferSize`.")
    func extract(_ entry: Entry, bufferSize: UInt32, skipCRC32: Bool = false,
                 progress: Progress? = nil, consumer: Consumer) throws -> CRC32 {
        try self.extract(entry, bufferSize: Int(bufferSize), skipCRC32: skipCRC32,
                         progress: progress, consumer: consumer)
    }

    @available(*, deprecated,
                renamed: "Archive.extract(_:to:bufferSize:skipCRC32:symlinksValidWithin:progress:)")
    func extract(_ entry: Entry, to url: URL, bufferSize: Int = defaultReadChunkSize,
                 skipCRC32: Bool = false,
                 allowUncontainedSymlinks: Bool,
                 progress: Progress? = nil) throws -> CRC32 {
        var symlinksValidWithin: URL?
        if allowUncontainedSymlinks {
            symlinksValidWithin = URL.rootFS
        }
        return try self.extract(entry, to: url, bufferSize: bufferSize, skipCRC32: skipCRC32,
                                symlinksValidWithin: symlinksValidWithin, progress: progress)
    }
}
