//
//  FileManager+ZIPDeprecated.swift
//  ZIPFoundation
//
//  Copyright © 2017-2026 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
//

import Foundation

public extension FileManager {

    @available(*, deprecated, renamed: "unzipItem(at:to:skipCRC32:progress:pathEncoding:)")
    func unzipItem(at sourceURL: URL, to destinationURL: URL, skipCRC32: Bool = false,
                   progress: Progress? = nil, preferredEncoding: String.Encoding?) throws {
        try self.unzipItem(at: sourceURL, to: destinationURL, skipCRC32: skipCRC32,
                           progress: progress, pathEncoding: preferredEncoding)
    }

    @available(*, deprecated,
                renamed: "unzipItem(at:to:skipCRC32:symlinksValidWithin:progress:pathEncoding:)")
    func unzipItem(at sourceURL: URL, to destinationURL: URL,
                   skipCRC32: Bool = false, allowUncontainedSymlinks: Bool,
                   progress: Progress? = nil, pathEncoding: String.Encoding? = nil) throws {
        let symlinksValidWithin = allowUncontainedSymlinks ? URL.rootFS : nil
        try self.unzipItem(at: sourceURL, to: destinationURL, skipCRC32: skipCRC32,
                           symlinksValidWithin: symlinksValidWithin,
                           progress: progress, pathEncoding: pathEncoding)
    }
}
