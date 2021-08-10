//
//  Entry+ZIP64.swift
//  ZIPFoundation
//
//  Copyright © 2017-2021 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
//

import Foundation

extension Entry {
    enum EntryError: Error {
        case invalidDataError
    }

    struct ZIP64ExtendedInformation {
        let headerID: UInt16 = ExtraFieldHeaderID.zip64ExtendedInformation.rawValue
        let dataSize: UInt16
        let uncompressedSize: Int64
        let compressedSize: Int64
        let relativeOffsetOfLocalHeader: Int64
        let diskNumberStart: UInt32
    }
}

extension Entry.ZIP64ExtendedInformation {
    enum Field {
        case uncompressedSize
        case compressedSize
        case relativeOffsetOfLocalHeader
        case diskNumberStart

        var size: Int {
            switch self {
            case .uncompressedSize, .compressedSize, .relativeOffsetOfLocalHeader:
                return 8
            case .diskNumberStart:
                return 4
            }
        }
    }

    var data: Data {
        var headerID = self.headerID
        var dataSize = self.dataSize
        var uncompressedSize = self.uncompressedSize
        var compressedSize = self.compressedSize
        var relativeOffsetOfLFH = self.relativeOffsetOfLocalHeader
        var diskNumberStart = self.diskNumberStart
        var data = Data()
        withUnsafePointer(to: &headerID, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &dataSize, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        if uncompressedSize != 0 || compressedSize != 0 {
            withUnsafePointer(to: &uncompressedSize, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
            withUnsafePointer(to: &compressedSize, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        }
        if relativeOffsetOfLocalHeader != 0 {
            withUnsafePointer(to: &relativeOffsetOfLFH, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        }
        if diskNumberStart != 0 {
            withUnsafePointer(to: &diskNumberStart, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        }
        return data
    }

    init?(data: Data, fields: [Field]) {
        let headerLength = 4
        guard fields.reduce(0, { $0 + $1.size }) + headerLength == data.count else { return nil }
        var readOffset = headerLength
        func value<T>(of field: Field) throws -> T where T: BinaryInteger {
            if fields.contains(field) {
                defer {
                    readOffset += MemoryLayout<T>.size
                }
                guard readOffset + field.size <= data.count else {
                    throw Entry.EntryError.invalidDataError
                }
                return data.scanValue(start: readOffset)
            } else {
                return 0
            }
        }
        do {
            dataSize = data.scanValue(start: 2)
            uncompressedSize = try value(of: .uncompressedSize)
            compressedSize = try value(of: .compressedSize)
            relativeOffsetOfLocalHeader = try value(of: .relativeOffsetOfLocalHeader)
            diskNumberStart = try value(of: .diskNumberStart)
        } catch {
            return nil
        }
    }

    static func scanForZIP64Field(in data: Data, fields: [Field]) -> Entry.ZIP64ExtendedInformation? {
        guard !data.isEmpty else { return nil }
        var offset = 0
        var headerID: UInt16
        var dataSize: UInt16
        let extraFieldLength = data.count
        while offset < extraFieldLength - 4 {
            headerID = data.scanValue(start: offset)
            dataSize = data.scanValue(start: offset + 2)
            let nextOffset = offset + 4 + Int(dataSize)
            guard nextOffset <= extraFieldLength else { return nil }
            if headerID == ExtraFieldHeaderID.zip64ExtendedInformation.rawValue {
                return Entry.ZIP64ExtendedInformation(data: data.subdata(in: offset..<nextOffset), fields: fields)
            }
            offset = nextOffset
        }
        return nil
    }
}
