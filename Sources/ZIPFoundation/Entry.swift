//
//  Entry.swift
//  ZIPFoundation
//
//  Copyright © 2017-2021 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
//

import Foundation
import CoreFoundation

/// A value that represents a file, a directory or a symbolic link within a ZIP `Archive`.
///
/// You can retrieve instances of `Entry` from an `Archive` via subscripting or iteration.
/// Entries are identified by their `path`.
public struct Entry: Equatable {
    /// The type of an `Entry` in a ZIP `Archive`.
    public enum EntryType: Int {
        /// Indicates a regular file.
        case file
        /// Indicates a directory.
        case directory
        /// Indicates a symbolic link.
        case symlink

        init(mode: mode_t) {
            switch mode & S_IFMT {
            case S_IFDIR:
                self = .directory
            case S_IFLNK:
                self = .symlink
            default:
                self = .file
            }
        }
    }

    enum OSType: UInt {
        case msdos = 0
        case unix = 3
        case osx = 19
        case unused = 20
    }

    struct LocalFileHeader: DataSerializable {
        let localFileHeaderSignature = UInt32(localFileHeaderStructSignature)
        let versionNeededToExtract: UInt16
        let generalPurposeBitFlag: UInt16
        let compressionMethod: UInt16
        let lastModFileTime: UInt16
        let lastModFileDate: UInt16
        let crc32: UInt32
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let fileNameLength: UInt16
        let extraFieldLength: UInt16
        static let size = 30
        let fileNameData: Data
        let extraFieldData: Data
        var extraFields: [ExtensibleDataField]?
    }

    struct DataDescriptor<T: BinaryInteger>: DataSerializable {
        let data: Data
        let dataDescriptorSignature = UInt32(dataDescriptorStructSignature)
        let crc32: UInt32
        // For normal archives, the compressed and uncompressed sizes are 4 bytes each.
        // For ZIP64 format archives, the compressed and uncompressed sizes are 8 bytes each.
        let compressedSize: T
        let uncompressedSize: T
        static var memoryLengthOfSize: Int { MemoryLayout<T>.size }
        static var size: Int { memoryLengthOfSize * 2 + 8 } // 16
    }

    typealias DefaultDataDescriptor = DataDescriptor<UInt32>
    typealias ZIP64DataDescriptor = DataDescriptor<Int64>

    struct CentralDirectoryStructure: DataSerializable {
        let centralDirectorySignature = UInt32(centralDirectoryStructSignature)
        let versionMadeBy: UInt16
        let versionNeededToExtract: UInt16
        let generalPurposeBitFlag: UInt16
        let compressionMethod: UInt16
        let lastModFileTime: UInt16
        let lastModFileDate: UInt16
        let crc32: UInt32
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let fileNameLength: UInt16
        let extraFieldLength: UInt16
        let fileCommentLength: UInt16
        let diskNumberStart: UInt16
        let internalFileAttributes: UInt16
        let externalFileAttributes: UInt32
        let relativeOffsetOfLocalHeader: UInt32
        static let size = 46
        let fileNameData: Data
        let extraFieldData: Data
        let fileCommentData: Data

        var extraFields: [ExtensibleDataField]?
        var usesDataDescriptor: Bool { return (self.generalPurposeBitFlag & (1 << 3 )) != 0 }
        var usesUTF8PathEncoding: Bool { return (self.generalPurposeBitFlag & (1 << 11 )) != 0 }
        var isEncrypted: Bool { return (self.generalPurposeBitFlag & (1 << 0)) != 0 }
        var isZIP64: Bool {
            // If zip64 extended information is existing, try to treat cd as zip64 format
            // even if the version needed to extract is lower than 4.5
            return UInt8(truncatingIfNeeded: self.versionNeededToExtract) >= 45 || zip64ExtendedInformation != nil
        }
    }
    /// Returns the `path` of the receiver within a ZIP `Archive` using a given encoding.
    ///
    /// - Parameters:
    ///   - encoding: `String.Encoding`
    public func path(using encoding: String.Encoding) -> String {
        return String(data: self.centralDirectoryStructure.fileNameData, encoding: encoding) ?? ""
    }
    /// The `path` of the receiver within a ZIP `Archive`.
    public var path: String {
        let dosLatinUS = 0x400
        let dosLatinUSEncoding = CFStringEncoding(dosLatinUS)
        let dosLatinUSStringEncoding = CFStringConvertEncodingToNSStringEncoding(dosLatinUSEncoding)
        let codepage437 = String.Encoding(rawValue: dosLatinUSStringEncoding)
        let encoding = self.centralDirectoryStructure.usesUTF8PathEncoding ? .utf8 : codepage437
        return self.path(using: encoding)
    }
    /// The file attributes of the receiver as key/value pairs.
    ///
    /// Contains the modification date and file permissions.
    public var fileAttributes: [FileAttributeKey: Any] {
        return FileManager.attributes(from: self)
    }
    /// The `CRC32` checksum of the receiver.
    ///
    /// - Note: Always returns `0` for entries of type `EntryType.directory`.
    public var checksum: CRC32 {
        var checksum = self.centralDirectoryStructure.crc32
        if self.centralDirectoryStructure.usesDataDescriptor {
            guard let dataDescriptor = self.dataDescriptor else { return 0 }
            checksum = dataDescriptor.crc32
        }
        return checksum
    }
    /// The `EntryType` of the receiver.
    public var type: EntryType {
        // OS Type is stored in the upper byte of versionMadeBy
        let osTypeRaw = self.centralDirectoryStructure.versionMadeBy >> 8
        let osType = OSType(rawValue: UInt(osTypeRaw)) ?? .unused
        var isDirectory = self.path.hasSuffix("/")
        switch osType {
        case .unix, .osx:
            let mode = mode_t(self.centralDirectoryStructure.externalFileAttributes >> 16) & S_IFMT
            switch mode {
            case S_IFREG:
                return .file
            case S_IFDIR:
                return .directory
            case S_IFLNK:
                return .symlink
            default:
                return isDirectory ? .directory : .file
            }
        case .msdos:
            isDirectory = isDirectory || ((centralDirectoryStructure.externalFileAttributes >> 4) == 0x01)
            fallthrough // For all other OSes we can only guess based on the directory suffix char
        default: return isDirectory ? .directory : .file
        }
    }
    /// The size of the receiver's compressed data.
    public var compressedSize: Int64 {
        if centralDirectoryStructure.isZIP64 {
            return zip64DataDescriptor?.compressedSize ?? centralDirectoryStructure.exactCompressedSize
        } else {
            return Int64(dataDescriptor?.compressedSize ?? centralDirectoryStructure.compressedSize)
        }
    }
    /// The size of the receiver's uncompressed data.
    public var uncompressedSize: Int64 {
        if centralDirectoryStructure.isZIP64 {
            return zip64DataDescriptor?.uncompressedSize ?? centralDirectoryStructure.exactUncompressedSize
        } else {
            return Int64(dataDescriptor?.uncompressedSize ?? centralDirectoryStructure.uncompressedSize)
        }
    }
    /// The combined size of the local header, the data and the optional data descriptor.
    var localSize: Int64 {
        let localFileHeader = self.localFileHeader
        var extraDataLength = Int(localFileHeader.fileNameLength)
        extraDataLength += Int(localFileHeader.extraFieldLength)
        var size: Int64 = Int64(LocalFileHeader.size + extraDataLength)
        let isCompressed = localFileHeader.compressionMethod != CompressionMethod.none.rawValue
        size += isCompressed ? self.compressedSize : self.uncompressedSize
        if centralDirectoryStructure.isZIP64 {
            size += self.zip64DataDescriptor != nil ? Int64(ZIP64DataDescriptor.size) : 0
        } else {
            size += self.dataDescriptor != nil ? Int64(DefaultDataDescriptor.size) : 0
        }
        return size
    }
    var dataOffset: Int64 {
        var dataOffset = self.centralDirectoryStructure.exactRelativeOffsetOfLocalHeader
        dataOffset += Int64(LocalFileHeader.size)
        dataOffset += Int64(self.localFileHeader.fileNameLength)
        dataOffset += Int64(self.localFileHeader.extraFieldLength)
        return dataOffset
    }
    let centralDirectoryStructure: CentralDirectoryStructure
    let localFileHeader: LocalFileHeader
    let dataDescriptor: DefaultDataDescriptor?
    let zip64DataDescriptor: ZIP64DataDescriptor?

    public static func == (lhs: Entry, rhs: Entry) -> Bool {
        return lhs.path == rhs.path
            && lhs.localFileHeader.crc32 == rhs.localFileHeader.crc32
            && lhs.centralDirectoryStructure.exactRelativeOffsetOfLocalHeader
            == rhs.centralDirectoryStructure.exactRelativeOffsetOfLocalHeader
    }

    init?(centralDirectoryStructure: CentralDirectoryStructure,
          localFileHeader: LocalFileHeader,
          dataDescriptor: DefaultDataDescriptor? = nil,
          zip64DataDescriptor: ZIP64DataDescriptor? = nil) {
        // We currently don't support encrypted archives
        guard !centralDirectoryStructure.isEncrypted else { return nil }
        self.centralDirectoryStructure = centralDirectoryStructure
        self.localFileHeader = localFileHeader
        self.dataDescriptor = dataDescriptor
        self.zip64DataDescriptor = zip64DataDescriptor
    }
}

extension Entry.LocalFileHeader {
    var data: Data {
        var localFileHeaderSignature = self.localFileHeaderSignature
        var versionNeededToExtract = self.versionNeededToExtract
        var generalPurposeBitFlag = self.generalPurposeBitFlag
        var compressionMethod = self.compressionMethod
        var lastModFileTime = self.lastModFileTime
        var lastModFileDate = self.lastModFileDate
        var crc32 = self.crc32
        var compressedSize = self.compressedSize
        var uncompressedSize = self.uncompressedSize
        var fileNameLength = self.fileNameLength
        var extraFieldLength = self.extraFieldLength
        var data = Data()
        withUnsafePointer(to: &localFileHeaderSignature, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &versionNeededToExtract, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &generalPurposeBitFlag, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &compressionMethod, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &lastModFileTime, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &lastModFileDate, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &crc32, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &compressedSize, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &uncompressedSize, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &fileNameLength, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &extraFieldLength, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        data.append(self.fileNameData)
        data.append(self.extraFieldData)
        return data
    }

    init?(data: Data, additionalDataProvider provider: (Int) throws -> Data) {
        guard data.count == Entry.LocalFileHeader.size else { return nil }
        guard data.scanValue(start: 0) == localFileHeaderSignature else { return nil }
        self.versionNeededToExtract = data.scanValue(start: 4)
        self.generalPurposeBitFlag = data.scanValue(start: 6)
        self.compressionMethod = data.scanValue(start: 8)
        self.lastModFileTime = data.scanValue(start: 10)
        self.lastModFileDate = data.scanValue(start: 12)
        self.crc32 = data.scanValue(start: 14)
        self.compressedSize = data.scanValue(start: 18)
        self.uncompressedSize = data.scanValue(start: 22)
        self.fileNameLength = data.scanValue(start: 26)
        self.extraFieldLength = data.scanValue(start: 28)
        let additionalDataLength = Int(self.fileNameLength) + Int(self.extraFieldLength)
        guard let additionalData = try? provider(additionalDataLength) else { return nil }
        guard additionalData.count == additionalDataLength else { return nil }
        var subRangeStart = 0
        var subRangeEnd = Int(self.fileNameLength)
        self.fileNameData = additionalData.subdata(in: subRangeStart..<subRangeEnd)
        subRangeStart += Int(self.fileNameLength)
        subRangeEnd = subRangeStart + Int(self.extraFieldLength)
        self.extraFieldData = additionalData.subdata(in: subRangeStart..<subRangeEnd)
        if let zip64ExtendedInformation = Entry.ZIP64ExtendedInformation.scanForZIP64Field(in: self.extraFieldData,
                                                                                           fields: self.validFields) {
            self.extraFields = [zip64ExtendedInformation]
        }
    }
}

extension Entry.CentralDirectoryStructure {
    var data: Data {
        var centralDirectorySignature = self.centralDirectorySignature
        var versionMadeBy = self.versionMadeBy
        var versionNeededToExtract = self.versionNeededToExtract
        var generalPurposeBitFlag = self.generalPurposeBitFlag
        var compressionMethod = self.compressionMethod
        var lastModFileTime = self.lastModFileTime
        var lastModFileDate = self.lastModFileDate
        var crc32 = self.crc32
        var compressedSize = self.compressedSize
        var uncompressedSize = self.uncompressedSize
        var fileNameLength = self.fileNameLength
        var extraFieldLength = self.extraFieldLength
        var fileCommentLength = self.fileCommentLength
        var diskNumberStart = self.diskNumberStart
        var internalFileAttributes = self.internalFileAttributes
        var externalFileAttributes = self.externalFileAttributes
        var relativeOffsetOfLocalHeader = self.relativeOffsetOfLocalHeader
        var data = Data()
        withUnsafePointer(to: &centralDirectorySignature, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &versionMadeBy, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &versionNeededToExtract, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &generalPurposeBitFlag, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &compressionMethod, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &lastModFileTime, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &lastModFileDate, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &crc32, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &compressedSize, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &uncompressedSize, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &fileNameLength, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &extraFieldLength, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &fileCommentLength, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &diskNumberStart, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &internalFileAttributes, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &externalFileAttributes, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &relativeOffsetOfLocalHeader, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        data.append(self.fileNameData)
        data.append(self.extraFieldData)
        data.append(self.fileCommentData)
        return data
    }

    init?(data: Data, additionalDataProvider provider: (Int) throws -> Data) {
        guard data.count == Entry.CentralDirectoryStructure.size else { return nil }
        guard data.scanValue(start: 0) == centralDirectorySignature else { return nil }
        self.versionMadeBy = data.scanValue(start: 4)
        self.versionNeededToExtract = data.scanValue(start: 6)
        self.generalPurposeBitFlag = data.scanValue(start: 8)
        self.compressionMethod = data.scanValue(start: 10)
        self.lastModFileTime = data.scanValue(start: 12)
        self.lastModFileDate = data.scanValue(start: 14)
        self.crc32 = data.scanValue(start: 16)
        self.compressedSize = data.scanValue(start: 20)
        self.uncompressedSize = data.scanValue(start: 24)
        self.fileNameLength = data.scanValue(start: 28)
        self.extraFieldLength = data.scanValue(start: 30)
        self.fileCommentLength = data.scanValue(start: 32)
        self.diskNumberStart = data.scanValue(start: 34)
        self.internalFileAttributes = data.scanValue(start: 36)
        self.externalFileAttributes = data.scanValue(start: 38)
        self.relativeOffsetOfLocalHeader = data.scanValue(start: 42)
        let additionalDataLength = Int(self.fileNameLength) + Int(self.extraFieldLength) + Int(self.fileCommentLength)
        guard let additionalData = try? provider(additionalDataLength) else { return nil }
        guard additionalData.count == additionalDataLength else { return nil }
        var subRangeStart = 0
        var subRangeEnd = Int(self.fileNameLength)
        self.fileNameData = additionalData.subdata(in: subRangeStart..<subRangeEnd)
        subRangeStart += Int(self.fileNameLength)
        subRangeEnd = subRangeStart + Int(self.extraFieldLength)
        self.extraFieldData = additionalData.subdata(in: subRangeStart..<subRangeEnd)
        subRangeStart += Int(self.extraFieldLength)
        subRangeEnd = subRangeStart + Int(self.fileCommentLength)
        self.fileCommentData = additionalData.subdata(in: subRangeStart..<subRangeEnd)
        if let zip64ExtendedInformation = Entry.ZIP64ExtendedInformation.scanForZIP64Field(in: self.extraFieldData,
                                                                                           fields: self.validFields) {
            self.extraFields = [zip64ExtendedInformation]
        }
    }

    init(localFileHeader: Entry.LocalFileHeader, fileAttributes: UInt32, relativeOffset: UInt32,
         extraField: (length: UInt16, data: Data)) {
        versionMadeBy = UInt16(789)
        versionNeededToExtract = localFileHeader.versionNeededToExtract
        generalPurposeBitFlag = localFileHeader.generalPurposeBitFlag
        compressionMethod = localFileHeader.compressionMethod
        lastModFileTime = localFileHeader.lastModFileTime
        lastModFileDate = localFileHeader.lastModFileDate
        crc32 = localFileHeader.crc32
        compressedSize = localFileHeader.compressedSize
        uncompressedSize = localFileHeader.uncompressedSize
        fileNameLength = localFileHeader.fileNameLength
        extraFieldLength = extraField.length
        fileCommentLength = UInt16(0)
        diskNumberStart = UInt16(0)
        internalFileAttributes = UInt16(0)
        externalFileAttributes = fileAttributes
        relativeOffsetOfLocalHeader = relativeOffset
        fileNameData = localFileHeader.fileNameData
        extraFieldData = extraField.data
        fileCommentData = Data()
        if let zip64ExtendedInformation = Entry.ZIP64ExtendedInformation.scanForZIP64Field(in: self.extraFieldData,
                                                                                           fields: self.validFields) {
            self.extraFields = [zip64ExtendedInformation]
        }
    }

    init(centralDirectoryStructure: Entry.CentralDirectoryStructure,
         zip64ExtendedInformation: Entry.ZIP64ExtendedInformation?, relativeOffset: UInt32) {
        if let existingInfo = zip64ExtendedInformation {
            extraFieldData = existingInfo.data
            versionNeededToExtract = max(centralDirectoryStructure.versionNeededToExtract, zip64Version)
        } else {
            extraFieldData = Data()
            if centralDirectoryStructure.versionNeededToExtract < zip64Version {
                versionNeededToExtract = centralDirectoryStructure.versionNeededToExtract
            } else {
                versionNeededToExtract = UInt16(20)
            }
        }
        extraFieldLength = UInt16(extraFieldData.count)
        relativeOffsetOfLocalHeader = relativeOffset
        versionMadeBy = centralDirectoryStructure.versionMadeBy
        generalPurposeBitFlag = centralDirectoryStructure.generalPurposeBitFlag
        compressionMethod = centralDirectoryStructure.compressionMethod
        lastModFileTime = centralDirectoryStructure.lastModFileTime
        lastModFileDate = centralDirectoryStructure.lastModFileDate
        crc32 = centralDirectoryStructure.crc32
        compressedSize = centralDirectoryStructure.compressedSize
        uncompressedSize = centralDirectoryStructure.uncompressedSize
        fileNameLength = centralDirectoryStructure.fileNameLength
        fileCommentLength = centralDirectoryStructure.fileCommentLength
        diskNumberStart = centralDirectoryStructure.diskNumberStart
        internalFileAttributes = centralDirectoryStructure.internalFileAttributes
        externalFileAttributes = centralDirectoryStructure.externalFileAttributes
        fileNameData = centralDirectoryStructure.fileNameData
        fileCommentData = centralDirectoryStructure.fileCommentData
        if let zip64ExtendedInformation = Entry.ZIP64ExtendedInformation.scanForZIP64Field(in: self.extraFieldData,
                                                                                           fields: self.validFields) {
            self.extraFields = [zip64ExtendedInformation]
        }
    }
}

extension Entry.CentralDirectoryStructure {
    public var exactCompressedSize: Int64 {
        if isZIP64, let compressedSize = zip64ExtendedInformation?.compressedSize, compressedSize > 0 {
            return compressedSize
        } else {
            return Int64(compressedSize)
        }
    }
    public var exactUncompressedSize: Int64 {
        if isZIP64, let uncompressedSize = zip64ExtendedInformation?.uncompressedSize, uncompressedSize > 0 {
            return uncompressedSize
        } else {
            return Int64(uncompressedSize)
        }
    }
    public var exactRelativeOffsetOfLocalHeader: Int64 {
        if isZIP64, let offset = zip64ExtendedInformation?.relativeOffsetOfLocalHeader, offset > 0 {
            return offset
        } else {
            return Int64(relativeOffsetOfLocalHeader)
        }
    }
    public var exactDiskNumberStart: UInt32 {
        if isZIP64, let diskNumberStart = zip64ExtendedInformation?.diskNumberStart, diskNumberStart > 0 {
            return diskNumberStart
        } else {
            return UInt32(diskNumberStart)
        }
    }
}

extension Entry.DataDescriptor {
    init?(data: Data, additionalDataProvider provider: (Int) throws -> Data) {
        guard data.count == Self.size else { return nil }
        let signature: UInt32 = data.scanValue(start: 0)
        // The DataDescriptor signature is not mandatory so we have to re-arrange the input data if it is missing.
        var readOffset = 0
        if signature == self.dataDescriptorSignature { readOffset = 4 }
        self.crc32 = data.scanValue(start: readOffset)
        readOffset += MemoryLayout<UInt32>.size
        self.compressedSize = data.scanValue(start: readOffset)
        readOffset += Self.memoryLengthOfSize
        self.uncompressedSize = data.scanValue(start: readOffset)
        // Our add(_ entry:) methods always maintain compressed & uncompressed
        // sizes and so we don't need a data descriptor for newly added entries.
        // Data descriptors of already existing entries are manually preserved
        // when copying those entries to the tempArchive during remove(_ entry:).
        self.data = Data()
    }
}
