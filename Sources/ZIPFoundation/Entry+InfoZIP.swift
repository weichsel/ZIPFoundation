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

    /// Scans the extra field data of the receiver for an Info-ZIP Unicode Path that is valid for its file name.
    ///
    /// Every initializer derives `infoZIPUnicodePath` with this method after it has set the extra field data.
    ///
    /// - Returns: The validated path or `nil` if there is no usable Unicode Path field.
    func scanForInfoZIPUnicodePath() -> String? {
        // The Unicode Path is not needed if the file name is flagged as UTF-8 encoded.
        guard self.usesUTF8PathEncoding == false else { return nil }
        return Self.scanForInfoZIPUnicodePath(in: self.extraFieldData, fileNameData: self.fileNameData)
    }

    /// Scans extra field data for an Info-ZIP Unicode Path extra field (APPNOTE.TXT 4.6.9).
    ///
    /// The field is only used if its version is not newer than 1 and if its CRC32 matches the checksum of
    /// `fileNameData`.
    /// A field whose path disagrees with `fileNameData` about a trailing path delimiter is not usable either,
    /// because the type of an entry depends on the file name of its header.
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
            buffer.forEachExtraField { (headerID, fieldRange) in
                guard headerID == Archive.ExtraFieldHeaderID.infoZIPUnicodePath.rawValue else { return true }
                let fieldData = UnsafeRawBufferPointer(rebasing: buffer[fieldRange].dropFirst(headerSize))
                guard let path = self.infoZIPUnicodePath(from: fieldData, fileNameData: fileNameData) else {
                    return false
                }
                unicodePath = path
                return true
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
        // The entry type is derived from the file name of the header. A path that disagrees with it about
        // the trailing path delimiter would turn a file into a directory path or vice versa.
        let pathDelimiter = UInt8(ascii: "/")
        guard (nameBytes.last == pathDelimiter) == (fileNameData.last == pathDelimiter) else { return nil }
        return String(bytes: nameBytes, encoding: .utf8)
    }
}
