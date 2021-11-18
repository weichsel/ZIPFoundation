//
//  Archive+WritingDeprecated.swift
//  ZIPFoundation
//
//  Copyright © 2017-2021 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
//

import Foundation

public extension Archive {

    @available(*, deprecated, message: "Please use `Int64` for `uncompressedSize` and provider `position`.")
    func addEntry(with path: String, type: Entry.EntryType, uncompressedSize: UInt32,
                  modificationDate: Date = Date(), permissions: UInt16? = nil,
                  compressionMethod: CompressionMethod = .none, bufferSize: Int = defaultWriteChunkSize,
                  progress: Progress? = nil, provider: (_ position: Int, _ size: Int) throws -> Data) throws {
        let newProvider: Provider = { try provider(Int($0), $1) }
        try self.addEntry(with: path, type: type, uncompressedSize: Int64(uncompressedSize),
                          modificationDate: modificationDate, permissions: permissions,
                          compressionMethod: compressionMethod, bufferSize: bufferSize,
                          progress: progress, provider: newProvider)
    }
}
