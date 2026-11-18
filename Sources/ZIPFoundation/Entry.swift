//
//  Entry.swift
//  ZIPFoundation
//
//  Copyright © 2017-2026 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/main/LICENSE for license information.
//

import Foundation
#if canImport(CoreFoundation)
import CoreFoundation
#endif
#if canImport(Android)
import Android
#endif

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
        /// Indicates whether the descriptor starts with the optional signature.
        let hasSignature: Bool
        static var memoryLengthOfSize: Int { MemoryLayout<T>.size }
        /// The size of a descriptor with a signature.
        static var size: Int { memoryLengthOfSize * 2 + 8 }
        /// The size of the receiver in the archive.
        var encodedSize: Int { self.hasSignature ? Self.size : Self.size - MemoryLayout<UInt32>.size }
    }

    typealias DefaultDataDescriptor = DataDescriptor<UInt32>
    typealias ZIP64DataDescriptor = DataDescriptor<UInt64>

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
            // If ZIP64 extended information is existing, try to treat cd as ZIP64 format
            // even if the version needed to extract is lower than 4.5
            return UInt8(truncatingIfNeeded: self.versionNeededToExtract) >= 45 || zip64ExtendedInformation != nil
        }
    }
    /// Returns the `path` of the receiver within a ZIP `Archive` using a given encoding.
    ///
    /// - Parameters:
    ///   - encoding: `String.Encoding`
    public func path(using encoding: String.Encoding) -> String {
        return String(pathData: self.centralDirectoryStructure.fileNameData, encoding: encoding)
    }
    /// The `path` of the receiver within a ZIP `Archive`.
    ///
    /// Uses the encoding indicated by the header, defaulting to code page 437.
    /// To apply an archive's explicit path encoding, call `path(using:)` with that encoding.
    public var path: String {
        let encoding = self.centralDirectoryStructure.usesUTF8PathEncoding ? String.Encoding.utf8 : .codepage437
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
        // Some writers only store the checksum in the data descriptor. A descriptor whose sizes differ from
        // the central directory was not read from its actual position or is wrong, so its checksum is ignored.
        let centralDirectoryStructure = self.centralDirectoryStructure
        if centralDirectoryStructure.usesDataDescriptor {
            if let descriptor = self.zip64DataDescriptor, descriptor.matchesSizes(of: centralDirectoryStructure) {
                return descriptor.crc32
            }
            if let descriptor = self.dataDescriptor, descriptor.matchesSizes(of: centralDirectoryStructure) {
                return descriptor.crc32
            }
        }
        return centralDirectoryStructure.crc32
    }
    /// The `EntryType` of the receiver.
    public var type: EntryType {
        // OS Type is stored in the upper byte of versionMadeBy
        let osTypeRaw = self.centralDirectoryStructure.versionMadeBy >> 8
        let osType = OSType(rawValue: UInt(osTypeRaw)) ?? .unused
        var isDirectory = self.path.hasSuffix("/")
        switch osType {
        case .unix, .osx:
            // Use truncatingIfNeeded for safer conversion across platforms
            let modeValue = UInt16(truncatingIfNeeded: self.centralDirectoryStructure.externalFileAttributes >> 16)
            let mode = mode_t(modeValue) & S_IFMT
            switch mode {
            case S_IFREG:
                // Some libraries incorrectly mark directories as S_IFREG.
                // If the path has a trailing "/", it takes precedence over file type flags
                // and must be treated as a directory.
                return isDirectory ? .directory : .file
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
    /// Indicates whether or not the receiver is compressed.
    public var isCompressed: Bool {
        self.localFileHeader.compressionMethod != CompressionMethod.none.rawValue
    }
    /// The size of the receiver's compressed data.
    ///
    /// It is the size that the central directory states. A data descriptor or local file header that
    /// states another size is ignored. Uncompressed entries are read by this size as well.
    public var compressedSize: UInt64 {
        return self.centralDirectoryStructure.effectiveCompressedSize
    }
    /// The size of the receiver's uncompressed data.
    ///
    /// It is the size that the central directory states. A data descriptor or local file header that
    /// states another size is ignored.
    public var uncompressedSize: UInt64 {
        return self.centralDirectoryStructure.effectiveUncompressedSize
    }
    /// The number of bytes that reading the receiver delivers.
    var readSize: UInt64 {
        return self.isCompressed ? self.uncompressedSize : self.compressedSize
    }
    /// The combined size of the local header, the data and the optional data descriptor.
    var localSize: UInt64 {
        let localFileHeader = self.localFileHeader
        var extraDataLength = Int(localFileHeader.fileNameLength)
        extraDataLength += Int(localFileHeader.extraFieldLength)
        var size = UInt64(LocalFileHeader.size + extraDataLength)
        let dataSize = self.compressedSize
        // `dataSize` can't be trusted. Saturate, so that callers can reject sizes that exceed `Int64.max`.
        guard dataSize <= Int64.max else { return .max }
        size += dataSize
        // At most one of the descriptors is set. A ZIP64 entry can have a data descriptor with 4 byte sizes.
        if let zip64DataDescriptor = self.zip64DataDescriptor {
            size += UInt64(zip64DataDescriptor.encodedSize)
        } else if let dataDescriptor = self.dataDescriptor {
            size += UInt64(dataDescriptor.encodedSize)
        }
        return size
    }
    var dataOffset: UInt64 {
        var dataOffset = self.centralDirectoryStructure.effectiveRelativeOffsetOfLocalHeader
        dataOffset += UInt64(LocalFileHeader.size)
        dataOffset += UInt64(self.localFileHeader.fileNameLength)
        dataOffset += UInt64(self.localFileHeader.extraFieldLength)
        return dataOffset
    }
    let centralDirectoryStructure: CentralDirectoryStructure
    let localFileHeader: LocalFileHeader
    let dataDescriptor: DefaultDataDescriptor?
    let zip64DataDescriptor: ZIP64DataDescriptor?

    public static func == (lhs: Entry, rhs: Entry) -> Bool {
        return lhs.path == rhs.path
            && lhs.localFileHeader.crc32 == rhs.localFileHeader.crc32
            && lhs.centralDirectoryStructure.effectiveRelativeOffsetOfLocalHeader
            == rhs.centralDirectoryStructure.effectiveRelativeOffsetOfLocalHeader
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

extension Entry.CentralDirectoryStructure {

    init(localFileHeader: Entry.LocalFileHeader, fileAttributes: UInt32, relativeOffset: UInt32,
         extraField: (length: UInt16, data: Data)) {
        self.versionMadeBy = UInt16(789)
        self.versionNeededToExtract = localFileHeader.versionNeededToExtract
        self.generalPurposeBitFlag = localFileHeader.generalPurposeBitFlag
        self.compressionMethod = localFileHeader.compressionMethod
        self.lastModFileTime = localFileHeader.lastModFileTime
        self.lastModFileDate = localFileHeader.lastModFileDate
        self.crc32 = localFileHeader.crc32
        self.compressedSize = localFileHeader.compressedSize
        self.uncompressedSize = localFileHeader.uncompressedSize
        self.fileNameLength = localFileHeader.fileNameLength
        self.extraFieldLength = extraField.length
        self.fileCommentLength = UInt16(0)
        self.diskNumberStart = UInt16(0)
        self.internalFileAttributes = UInt16(0)
        self.externalFileAttributes = fileAttributes
        self.relativeOffsetOfLocalHeader = relativeOffset
        self.fileNameData = localFileHeader.fileNameData
        self.extraFieldData = extraField.data
        self.fileCommentData = Data()
        if let zip64ExtendedInformation = Entry.ZIP64ExtendedInformation.scanForZIP64Field(in: self.extraFieldData,
                                                                                           fields: self.validFields) {
            self.extraFields = [zip64ExtendedInformation]
        }
    }

    /// Creates a copy of `centralDirectoryStructure` for an entry that has been moved to `updatedOffset`.
    ///
    /// Existing ZIP64 extended information is replaced or removed, depending on which fields of the
    /// updated structure contain a ZIP64 placeholder. All other extra fields are preserved.
    /// Returns `nil` if the updated extra fields exceed the maximum extra field length.
    init?(centralDirectoryStructure: Entry.CentralDirectoryStructure, updatedOffset: UInt64) {
        let relativeOffset = updatedOffset < maxOffsetOfLocalFileHeader ? UInt32(updatedOffset) : UInt32.max
        var versionNeededToExtract = centralDirectoryStructure.versionNeededToExtract
        var extraFieldData = centralDirectoryStructure.extraFieldData
        let existingInfo = centralDirectoryStructure.zip64ExtendedInformation
        // An entry without ZIP64 extended information needs it, if it has been moved behind the maximum offset.
        // The remaining entries are written in the order of the central directory, so offsets can also increase.
        if existingInfo != nil || relativeOffset == .max {
            // ZIP64 extended information that is no longer needed is removed.
            let zip64FieldData = centralDirectoryStructure.zip64FieldData(forOffset: updatedOffset,
                                                                          usingPlaceholder: relativeOffset == .max)
            // ZIP64 extended information requires version 4.5. An entry with a data descriptor also stays marked
            // as ZIP64 if its ZIP64 extended information is removed. Otherwise its data descriptor would be read
            // with a different size. Only the lower byte holds the version.
            let needsZIP64Version = zip64FieldData != nil || centralDirectoryStructure.usesDataDescriptor
            if needsZIP64Version,
               UInt8(truncatingIfNeeded: versionNeededToExtract) < UInt8(Archive.Version.v45.rawValue) {
                versionNeededToExtract = (versionNeededToExtract & 0xff00) | Archive.Version.v45.rawValue
            }
            // New ZIP64 extended information precedes the existing extra fields. Data that follows the last
            // well-formed extra field stays at the end that way.
            if existingInfo != nil {
                extraFieldData = Entry.ZIP64ExtendedInformation
                    .extraFieldData(replacingZIP64FieldIn: extraFieldData, with: zip64FieldData)
            } else if let zip64FieldData = zip64FieldData {
                extraFieldData = zip64FieldData + extraFieldData
            }
        }
        guard extraFieldData.count <= Int(UInt16.max) else { return nil }
        self.extraFieldData = extraFieldData
        // The version is never lowered. It can also be required by other features of the entry,
        // like a ZIP64 data descriptor or its compression method.
        self.versionNeededToExtract = versionNeededToExtract
        self.extraFieldLength = UInt16(extraFieldData.count)
        self.relativeOffsetOfLocalHeader = relativeOffset
        self.versionMadeBy = centralDirectoryStructure.versionMadeBy
        self.generalPurposeBitFlag = centralDirectoryStructure.generalPurposeBitFlag
        self.compressionMethod = centralDirectoryStructure.compressionMethod
        self.lastModFileTime = centralDirectoryStructure.lastModFileTime
        self.lastModFileDate = centralDirectoryStructure.lastModFileDate
        self.crc32 = centralDirectoryStructure.crc32
        self.compressedSize = centralDirectoryStructure.compressedSize
        self.uncompressedSize = centralDirectoryStructure.uncompressedSize
        self.fileNameLength = centralDirectoryStructure.fileNameLength
        self.fileCommentLength = centralDirectoryStructure.fileCommentLength
        self.diskNumberStart = centralDirectoryStructure.diskNumberStart
        self.internalFileAttributes = centralDirectoryStructure.internalFileAttributes
        self.externalFileAttributes = centralDirectoryStructure.externalFileAttributes
        self.fileNameData = centralDirectoryStructure.fileNameData
        self.fileCommentData = centralDirectoryStructure.fileCommentData
        if let zip64ExtendedInformation = Entry.ZIP64ExtendedInformation.scanForZIP64Field(in: self.extraFieldData,
                                                                                           fields: self.validFields) {
            self.extraFields = [zip64ExtendedInformation]
        }
    }
}

extension Entry.CentralDirectoryStructure {

    /// Returns the ZIP64 extended information field of the receiver for an updated offset.
    ///
    /// - Returns: The serialized field or `nil` if the receiver doesn't need ZIP64 extended information.
    func zip64FieldData(forOffset offset: UInt64, usingPlaceholder: Bool) -> Data? {
        let existingInfo = self.zip64ExtendedInformation
        // The sizes and the disk number are unchanged. Only the placeholder of the offset can change.
        var fields = existingInfo == nil ? [] : self.validFields.filter { $0 != .relativeOffsetOfLocalHeader }
        if usingPlaceholder { fields.append(.relativeOffsetOfLocalHeader) }
        guard fields.isEmpty == false else { return nil }

        let emptyInfo = Entry.ZIP64ExtendedInformation(dataSize: 0, uncompressedSize: 0, compressedSize: 0,
                                                       relativeOffsetOfLocalHeader: 0, diskNumberStart: 0)
        return (existingInfo ?? emptyInfo).data(containing: fields, relativeOffsetOfLocalHeader: offset)
    }

    var effectiveCompressedSize: UInt64 {
        if self.isZIP64, self.compressedSize == .max,
           let compressedSize = self.zip64ExtendedInformation?.compressedSize {
            return compressedSize
        }
        return UInt64(compressedSize)
    }
    var effectiveUncompressedSize: UInt64 {
        if self.isZIP64, self.uncompressedSize == .max,
           let uncompressedSize = self.zip64ExtendedInformation?.uncompressedSize {
            return uncompressedSize
        }
        return UInt64(uncompressedSize)
    }
    var effectiveRelativeOffsetOfLocalHeader: UInt64 {
        if self.isZIP64, self.relativeOffsetOfLocalHeader == .max,
           let offset = self.zip64ExtendedInformation?.relativeOffsetOfLocalHeader {
            return offset
        }
        return UInt64(relativeOffsetOfLocalHeader)
    }
}
