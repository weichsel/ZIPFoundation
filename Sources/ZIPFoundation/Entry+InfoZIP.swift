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

extension Entry {

    struct InfoZIPUnicodePath: ExtensibleDataField {
        var headerID: UInt16 { Archive.ExtraFieldHeaderID.infoZIPUnicodePath.rawValue }
        let dataSize: UInt16
        let version: UInt8
        let nameCRC32: UInt32
        let unicodeName: Data
    }

    var infoZIPExtraField: InfoZIPUnicodePath? {
        let extraField = self.localFileHeader.extraFields?.first { $0 is InfoZIPUnicodePath }
        return extraField as? InfoZIPUnicodePath
    }
}

extension Entry.InfoZIPUnicodePath {

    static func scanForUnicodePath(in data: Data) -> Entry.InfoZIPUnicodePath? {
        guard data.isEmpty == false else { return nil }
        var offset = 0
        var headerID: UInt16
        var dataSize: UInt16
        let extraFieldLength = data.count
        let headerSize = 4

        while offset < extraFieldLength - headerSize {
            headerID = data.scanValue(start: offset)
            dataSize = data.scanValue(start: offset + 2)
            let nextOffset = offset + headerSize + Int(dataSize)
            guard nextOffset <= extraFieldLength else { return nil }

            // The field has to contain at least a version (1 byte) and the CRC32 of the header file name (4 bytes).
            if headerID == Archive.ExtraFieldHeaderID.infoZIPUnicodePath.rawValue, dataSize >= 5 {
                let fieldData = data.subdata(in: offset..<nextOffset)
                let version: UInt8 = fieldData.scanValue(start: 4)
                let nameCRC32: UInt32 = fieldData.scanValue(start: 5)
                let unicodeNameData = fieldData.subdata(in: 9..<fieldData.count)

                return Entry.InfoZIPUnicodePath(
                    dataSize: dataSize,
                    version: version,
                    nameCRC32: nameCRC32,
                    unicodeName: unicodeNameData
                )
            }
            offset = nextOffset
        }
        return nil
    }
}
