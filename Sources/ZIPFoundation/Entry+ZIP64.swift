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

/// An extra field of a header. It consists of a header ID, the size of its data and the data itself.
struct ExtraField {
    /// The size of the header ID and the data size that precede the data of every extra field.
    static let headerSize = 4
    let headerID: UInt16
    /// The bytes of the field, including its 4 byte header.
    let data: Data
}

/// The well-formed extra fields at the beginning of the extra field data of a header.
///
/// Iteration ends at the first field that claims more data than is available.
struct ExtraFields: Sequence, IteratorProtocol {

    /// The data that has not been returned as part of a field yet.
    ///
    /// After the iteration has ended, this is the data that follows the last well-formed field.
    private(set) var remainingData: Data

    /// - Parameter data: The untrusted extra field data of a header.
    init(_ data: Data) {
        self.remainingData = data
    }

    mutating func next() -> ExtraField? {
        guard self.remainingData.count >= ExtraField.headerSize else { return nil }
        let headerID = UInt16(littleEndian: self.remainingData.scanValue(start: 0))
        let dataSize = UInt16(littleEndian: self.remainingData.scanValue(start: 2))
        let fieldSize = ExtraField.headerSize + Int(dataSize)
        guard fieldSize <= self.remainingData.count else { return nil }
        let fieldData = self.remainingData.prefix(fieldSize)
        self.remainingData = self.remainingData.dropFirst(fieldSize)
        return ExtraField(headerID: headerID, data: fieldData)
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
    /// Indicates whether the extra field contains ZIP64 extended information, regardless of its fields.
    var hasZIP64ExtendedInformation: Bool {
        let zip64FieldID = Archive.ExtraFieldHeaderID.zip64ExtendedInformation.rawValue
        return ExtraFields(self.extraFieldData).contains { $0.headerID == zip64FieldID }
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
        return self.data(containing: fields, dataSize: self.dataSize,
                         relativeOffsetOfLocalHeader: self.relativeOffsetOfLocalHeader)
    }

    init?(data: Data, fields: [Field]) {
        let headerSize = ExtraField.headerSize
        guard fields.reduce(0, { $0 + $1.size }) + headerSize == data.count else { return nil }

        var readOffset = headerSize
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
    ///
    /// - Parameters:
    ///   - fields: The values to include. The size of the field data is derived from them.
    ///   - relativeOffsetOfLocalHeader: An offset that is stored instead of the offset of the receiver.
    func data(containing fields: [Field], relativeOffsetOfLocalHeader: UInt64? = nil) -> Data {
        return self.data(containing: fields, dataSize: UInt16(fields.reduce(0, { $0 + $1.size })),
                         relativeOffsetOfLocalHeader: relativeOffsetOfLocalHeader ?? self.relativeOffsetOfLocalHeader)
    }

    private func data(containing fields: [Field], dataSize: UInt16, relativeOffsetOfLocalHeader: UInt64) -> Data {
        var headerID = self.headerID
        var dataSize = dataSize
        var uncompressedSize = self.uncompressedSize
        var compressedSize = self.compressedSize
        var relativeOffsetOfLFH = relativeOffsetOfLocalHeader
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
    /// A replacement requires that `data` contains ZIP64 extended information.
    static func extraFieldData(replacingZIP64FieldIn data: Data, with zip64FieldData: Data?) -> Data {
        var updatedData = Data()
        var replacement = zip64FieldData
        // The iterator is advanced manually, because the data that follows the last field is needed afterwards.
        var fields = ExtraFields(data)
        while let field = fields.next() {
            if field.headerID != Archive.ExtraFieldHeaderID.zip64ExtendedInformation.rawValue {
                updatedData.append(field.data)
            } else if let zip64FieldData = replacement {
                // Only the first ZIP64 extended information field is replaced. Additional ones are removed.
                updatedData.append(zip64FieldData)
                replacement = nil
            }
        }
        updatedData.append(fields.remainingData)
        return updatedData
    }

    /// Scans extra field data for ZIP64 extended information that contains exactly the values of `fields`.
    ///
    /// Only the first ZIP64 extended information field is taken into account.
    static func scanForZIP64Field(in data: Data, fields: [Field]) -> Entry.ZIP64ExtendedInformation? {
        let zip64FieldID = Archive.ExtraFieldHeaderID.zip64ExtendedInformation.rawValue
        guard let zip64Field = ExtraFields(data).first(where: { $0.headerID == zip64FieldID }) else { return nil }
        return Entry.ZIP64ExtendedInformation(data: zip64Field.data, fields: fields)
    }
}
