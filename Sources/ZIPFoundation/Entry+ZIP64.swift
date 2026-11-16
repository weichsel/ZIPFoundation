//
//  Entry+ZIP64.swift
//  ZIPFoundation
//
//  Copyright © 2017-2026 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/main/LICENSE for license information.
//

import Foundation

protocol ExtensibleDataField {
    var headerID: UInt16 { get }
    var dataSize: UInt16 { get }
}

extension UnsafeRawBufferPointer {
    /// Calls `body` with the header ID and the range of each well-formed extra field in the receiver.
    ///
    /// The range includes the 4 byte header of the field. Iteration ends at the first field that claims
    /// more data than is available, or when `body` returns `false`.
    ///
    /// - Returns: The offset of the first byte that has not been passed to `body` as part of an accepted field.
    @discardableResult
    func forEachExtraField(_ body: (_ headerID: UInt16, _ fieldRange: Range<Int>) -> Bool) -> Int {
        let headerSize = 4
        var offset = 0
        while self.count - offset >= headerSize {
            let headerID = UInt16(littleEndian: self.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
            let dataSize = UInt16(littleEndian: self.loadUnaligned(fromByteOffset: offset + 2, as: UInt16.self))
            let nextOffset = offset + headerSize + Int(dataSize)
            guard nextOffset <= self.count, body(headerID, offset..<nextOffset) else { break }
            offset = nextOffset
        }
        return offset
    }
}

extension Entry {

    enum EntryError: Error {
        case missingPermissionsAttributeError
        case missingModificationDateAttributeError
    }

    struct ZIP64ExtendedInformation: ExtensibleDataField {
        let headerID: UInt16 = Archive.ExtraFieldHeaderID.zip64ExtendedInformation.rawValue
        let dataSize: UInt16
        static let headerSize: UInt16 = 4
        let uncompressedSize: UInt64
        let compressedSize: UInt64
        let relativeOffsetOfLocalHeader: UInt64
        let diskNumberStart: UInt32
    }

    var zip64ExtendedInformation: ZIP64ExtendedInformation? {
        self.centralDirectoryStructure.zip64ExtendedInformation
    }
}

typealias Field = Entry.ZIP64ExtendedInformation.Field

extension Entry.LocalFileHeader {
    var validFields: [Field] {
        var fields: [Field] = []
        if self.uncompressedSize == .max { fields.append(.uncompressedSize) }
        if self.compressedSize == .max { fields.append(.compressedSize) }
        return fields
    }
}

extension Entry.CentralDirectoryStructure {
    var validFields: [Field] {
        var fields: [Field] = []
        if self.uncompressedSize == .max { fields.append(.uncompressedSize) }
        if self.compressedSize == .max { fields.append(.compressedSize) }
        if self.relativeOffsetOfLocalHeader == .max { fields.append(.relativeOffsetOfLocalHeader) }
        if self.diskNumberStart == .max { fields.append(.diskNumberStart) }
        return fields
    }
    var zip64ExtendedInformation: Entry.ZIP64ExtendedInformation? {
        self.extraFields?.compactMap { $0 as? Entry.ZIP64ExtendedInformation }.first
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
        // Sizes are always stored as a pair. All other values are only stored if they are set.
        var fields: [Field] = []
        if self.uncompressedSize != 0 || self.compressedSize != 0 { fields += [.uncompressedSize, .compressedSize] }
        if self.relativeOffsetOfLocalHeader != 0 { fields.append(.relativeOffsetOfLocalHeader) }
        if self.diskNumberStart != 0 { fields.append(.diskNumberStart) }
        return self.data(containing: fields, dataSize: self.dataSize)
    }

    init?(data: Data, fields: [Field]) {
        let headerLength = 4
        guard fields.reduce(0, { $0 + $1.size }) + headerLength == data.count else { return nil }

        var readOffset = headerLength
        func value<T>(of field: Field) -> T where T: BinaryInteger {
            if fields.contains(field), readOffset + field.size <= data.count {
                defer { readOffset += MemoryLayout<T>.size }

                return data.scanValue(start: readOffset)
            } else {
                return 0
            }
        }

        self.dataSize = data.scanValue(start: 2)
        self.uncompressedSize = value(of: .uncompressedSize)
        self.compressedSize = value(of: .compressedSize)
        self.relativeOffsetOfLocalHeader = value(of: .relativeOffsetOfLocalHeader)
        self.diskNumberStart = value(of: .diskNumberStart)
    }

    /// Returns the serialized extra field. Only the values of `fields` are included.
    func data(containing fields: [Field]) -> Data {
        return self.data(containing: fields, dataSize: UInt16(fields.reduce(0, { $0 + $1.size })))
    }

    private func data(containing fields: [Field], dataSize: UInt16) -> Data {
        var headerID = self.headerID
        var dataSize = dataSize
        var uncompressedSize = self.uncompressedSize
        var compressedSize = self.compressedSize
        var relativeOffsetOfLFH = self.relativeOffsetOfLocalHeader
        var diskNumberStart = self.diskNumberStart
        var data = Data()
        withUnsafePointer(to: &headerID, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &dataSize, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        // The order of the values is fixed.
        if fields.contains(.uncompressedSize) {
            withUnsafePointer(to: &uncompressedSize, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        }
        if fields.contains(.compressedSize) {
            withUnsafePointer(to: &compressedSize, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        }
        if fields.contains(.relativeOffsetOfLocalHeader) {
            withUnsafePointer(to: &relativeOffsetOfLFH, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        }
        if fields.contains(.diskNumberStart) {
            withUnsafePointer(to: &diskNumberStart, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        }
        return data
    }

    /// Returns `data` with its ZIP64 extended information field replaced by `zip64FieldData`.
    ///
    /// Pass `nil` to remove the ZIP64 extended information. All other extra fields keep their position.
    /// Data that follows the last well-formed extra field is preserved too.
    static func extraFieldData(replacingZIP64FieldIn data: Data, with zip64FieldData: Data?) -> Data {
        var remainingData = Data()
        var replacement = zip64FieldData
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            let endOfFields = buffer.forEachExtraField { (headerID, fieldRange) in
                if headerID != Archive.ExtraFieldHeaderID.zip64ExtendedInformation.rawValue {
                    remainingData.append(contentsOf: UnsafeRawBufferPointer(rebasing: buffer[fieldRange]))
                } else if let zip64FieldData = replacement {
                    // Only the first ZIP64 extended information field is replaced. Additional ones are removed.
                    remainingData.append(zip64FieldData)
                    replacement = nil
                }
                return true
            }
            remainingData.append(contentsOf: UnsafeRawBufferPointer(rebasing: buffer[endOfFields...]))
        }
        // The existing field is not part of the well-formed fields. The replacement has to precede all other data.
        if let zip64FieldData = replacement { remainingData = zip64FieldData + remainingData }
        return remainingData
    }

    static func scanForZIP64Field(in data: Data, fields: [Field]) -> Entry.ZIP64ExtendedInformation? {
        guard data.isEmpty == false else { return nil }
        var offset = 0
        var headerID: UInt16
        var dataSize: UInt16
        let extraFieldLength = data.count
        let headerSize = Int(Entry.ZIP64ExtendedInformation.headerSize)
        while offset < extraFieldLength - headerSize {
            headerID = data.scanValue(start: offset)
            dataSize = data.scanValue(start: offset + 2)
            let nextOffset = offset + headerSize + Int(dataSize)
            guard nextOffset <= extraFieldLength else { return nil }
            if headerID == Archive.ExtraFieldHeaderID.zip64ExtendedInformation.rawValue {
                return Entry.ZIP64ExtendedInformation(data: data.subdata(in: offset..<nextOffset), fields: fields)
            }
            offset = nextOffset
        }
        return nil
    }
}
