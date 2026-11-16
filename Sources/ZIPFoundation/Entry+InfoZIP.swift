//
//  Entry+InfoZIP.swift
//  ZIPFoundation
//
//  Copyright © 2017-2026 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/main/LICENSE for license information.
//

import Foundation

extension Entry.CentralDirectoryStructure {

    /// Scans extra field data for an Info-ZIP Unicode Path extra field (APPNOTE.TXT 4.6.9).
    ///
    /// The field is only used if its version is not newer than 1 and if its CRC32 matches the checksum of
    /// `fileNameData`.
    /// Scanning stops at the first Unicode Path field that is not usable and at the first malformed extra field.
    /// If there is more than one usable field, the last one is used. This matches Info-ZIP's `unzip`.
    ///
    /// - Parameters:
    ///   - extraFieldData: The untrusted extra field data of a header.
    ///   - fileNameData: The file name of the same header.
    /// - Returns: The validated path or `nil` if `extraFieldData` contains no usable Unicode Path field.
    static func scanForInfoZIPUnicodePath(in extraFieldData: Data, fileNameData: Data) -> String? {
        let headerSize = 4
        // The smallest usable field consists of a header, a version (1 byte) and a CRC32 (4 bytes).
        guard extraFieldData.count >= headerSize + 5 else { return nil }
        return extraFieldData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> String? in
            var unicodePath: String?
            var offset = 0
            while buffer.count - offset >= headerSize {
                let headerID = UInt16(littleEndian: buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                let dataSize = UInt16(littleEndian: buffer.loadUnaligned(fromByteOffset: offset + 2, as: UInt16.self))
                let dataStart = offset + headerSize
                let dataEnd = dataStart + Int(dataSize)
                guard dataEnd <= buffer.count else { break }
                if headerID == Archive.ExtraFieldHeaderID.infoZIPUnicodePath.rawValue {
                    let fieldData = UnsafeRawBufferPointer(rebasing: buffer[dataStart..<dataEnd])
                    guard let path = self.infoZIPUnicodePath(from: fieldData, fileNameData: fileNameData) else { break }
                    unicodePath = path
                }
                offset = dataEnd
            }
            return unicodePath
        }
    }

    private static func infoZIPUnicodePath(from fieldData: UnsafeRawBufferPointer, fileNameData: Data) -> String? {
        // Info-ZIP's `unzip` only rejects versions that are newer than the supported version.
        let supportedVersion = UInt8(1)
        let nameOffset = 5
        guard fieldData.count >= nameOffset, fieldData[0] <= supportedVersion else { return nil }
        let nameCRC32 = UInt32(littleEndian: fieldData.loadUnaligned(fromByteOffset: 1, as: UInt32.self))
        guard nameCRC32 == fileNameData.crc32(checksum: 0) else { return nil }
        // Info-ZIP's `unzip` treats the name as a C string. It ends at the first NUL byte.
        let nameBytes = fieldData[nameOffset...].prefix { $0 != 0 }
        // A field without a name indicates that the file name of the header is UTF-8 encoded.
        // Like in `unzip`, this includes names that start with a NUL byte.
        guard nameBytes.isEmpty == false else { return String(data: fileNameData, encoding: .utf8) }
        return String(bytes: nameBytes, encoding: .utf8)
    }
}
