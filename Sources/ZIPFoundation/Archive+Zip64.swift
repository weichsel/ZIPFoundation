//
//  Archive+Zip64.swift
//  ZIPFoundation
//
//  Copyright © 2017-2021 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
//

import Foundation

/// The minimum version of zip64 format
public let zip64Version = UInt16(45)
let zip64EndOfCentralDirectoryRecordStructSignature = 0x06064b50
let zip64EndOfCentralDirectoryLocatorStructSignature = 0x07064b50

enum ExtraFieldHeaderID: UInt16 {
    case zip64ExtendedInformation = 0x0001
}

var maxUInt32 = UInt32.max
var maxUInt16 = UInt16.max

var maxCompressedSize: UInt32 { maxUInt32 }
var maxUncompressedSize: UInt32 { maxUInt32 }
var maxOffsetOfLocalFileHeader: UInt32 { maxUInt32 }
var maxOffsetOfCentralDirectory: UInt32 { maxUInt32 }
var maxSizeOfCentralDirectory: UInt32 { maxUInt32 }
var maxTotalNumberOfEntries: UInt16 { maxUInt16 }

extension Archive {
    struct Zip64EndOfCentralDirectory {
        let record: Zip64EndOfCentralDirectoryRecord
        let locator: Zip64EndOfCentralDirectoryLocator
    }
    
    struct Zip64EndOfCentralDirectoryRecord: DataSerializable {
        let zip64EndOfCentralDirectorySignature = UInt32(zip64EndOfCentralDirectoryRecordStructSignature)
        let sizeOfZip64EndOfCentralDirectoryRecord: UInt
        let versionMadeBy: UInt16
        let versionNeededToExtract: UInt16
        let numberOfDisk: UInt32
        let numberOfDiskStart: UInt32
        let totalNumberOfEntriesOnDisk: UInt
        let totalNumberOfEntriesInCentralDirectory: UInt
        let sizeOfCentralDirectory: UInt
        let offsetToStartOfCentralDirectory: UInt
        let zip64ExtensibleDataSector: Data
        static let size = 56
    }

    struct Zip64EndOfCentralDirectoryLocator: DataSerializable {
        let zip64EndOfCentralDirectoryLocatorSignature = UInt32(zip64EndOfCentralDirectoryLocatorStructSignature)
        let numberOfDiskWithZip64EOCDRecordStart: UInt32
        let relativeOffsetOfZip64EOCDRecord: UInt
        let totalNumberOfDisk: UInt32
        static let size = 20
    }
}

extension Archive.Zip64EndOfCentralDirectoryRecord {
    var data: Data {
        var zip64EOCDRecordSignature = self.zip64EndOfCentralDirectorySignature
        var sizeOfZip64EOCDRecord = self.sizeOfZip64EndOfCentralDirectoryRecord
        var versionMadeBy = self.versionMadeBy
        var versionNeededToExtract = self.versionNeededToExtract
        var numberOfDisk = self.numberOfDisk
        var numberOfDiskStart = self.numberOfDiskStart
        var totalNumberOfEntriesOnDisk = self.totalNumberOfEntriesOnDisk
        var totalNumberOfEntriesInCD = self.totalNumberOfEntriesInCentralDirectory
        var sizeOfCD = self.sizeOfCentralDirectory
        var offsetToStartOfCD = self.offsetToStartOfCentralDirectory
        var data = Data()
        withUnsafePointer(to: &zip64EOCDRecordSignature, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &sizeOfZip64EOCDRecord, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &versionMadeBy, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &versionNeededToExtract, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &numberOfDisk, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &numberOfDiskStart, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &totalNumberOfEntriesOnDisk, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &totalNumberOfEntriesInCD, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &sizeOfCD, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &offsetToStartOfCD, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        data.append(self.zip64ExtensibleDataSector)
        return data
    }

    init?(data: Data, additionalDataProvider provider: (Int) throws -> Data) {
        guard data.count == Archive.Zip64EndOfCentralDirectoryRecord.size else { return nil }
        guard data.scanValue(start: 0) == zip64EndOfCentralDirectorySignature else { return nil }
        self.sizeOfZip64EndOfCentralDirectoryRecord = data.scanValue(start: 4)
        self.versionMadeBy = data.scanValue(start: 12)
        self.versionNeededToExtract = data.scanValue(start: 14)
        guard self.versionNeededToExtract >= zip64Version else { return nil }
        self.numberOfDisk = data.scanValue(start: 16)
        self.numberOfDiskStart = data.scanValue(start: 20)
        self.totalNumberOfEntriesOnDisk = data.scanValue(start: 24)
        self.totalNumberOfEntriesInCentralDirectory = data.scanValue(start: 32)
        self.sizeOfCentralDirectory = data.scanValue(start: 40)
        self.offsetToStartOfCentralDirectory = data.scanValue(start: 48)
        self.zip64ExtensibleDataSector = Data()
    }

    init(record: Archive.Zip64EndOfCentralDirectoryRecord,
         numberOfEntriesOnDisk: UInt,
         numberOfEntriesInCD: UInt,
         sizeOfCentralDirectory: UInt,
         offsetToStartOfCD: UInt) {
        self.sizeOfZip64EndOfCentralDirectoryRecord = record.sizeOfZip64EndOfCentralDirectoryRecord
        self.versionMadeBy = record.versionMadeBy
        self.versionNeededToExtract = record.versionNeededToExtract
        self.numberOfDisk = record.numberOfDisk
        self.numberOfDiskStart = record.numberOfDiskStart
        self.totalNumberOfEntriesOnDisk = numberOfEntriesOnDisk
        self.totalNumberOfEntriesInCentralDirectory = numberOfEntriesInCD
        self.sizeOfCentralDirectory = sizeOfCentralDirectory
        self.offsetToStartOfCentralDirectory = offsetToStartOfCD
        self.zip64ExtensibleDataSector = record.zip64ExtensibleDataSector
    }
}

extension Archive.Zip64EndOfCentralDirectoryLocator {
    var data: Data {
        var zip64EOCDLocatorSignature = self.zip64EndOfCentralDirectoryLocatorSignature
        var numberOfDiskWithZip64EOCD = self.numberOfDiskWithZip64EOCDRecordStart
        var offsetOfZip64EOCDRecord = self.relativeOffsetOfZip64EOCDRecord
        var totalNumberOfDisk = self.totalNumberOfDisk
        var data = Data()
        withUnsafePointer(to: &zip64EOCDLocatorSignature, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &numberOfDiskWithZip64EOCD, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &offsetOfZip64EOCDRecord, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &totalNumberOfDisk, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        return data
    }

    init?(data: Data, additionalDataProvider provider: (Int) throws -> Data) {
        guard data.count == Archive.Zip64EndOfCentralDirectoryLocator.size else { return nil }
        guard data.scanValue(start: 0) == zip64EndOfCentralDirectoryLocatorSignature else { return nil }
        self.numberOfDiskWithZip64EOCDRecordStart = data.scanValue(start: 4)
        self.relativeOffsetOfZip64EOCDRecord = data.scanValue(start: 8)
        self.totalNumberOfDisk = data.scanValue(start: 16)
    }

    init(locator: Archive.Zip64EndOfCentralDirectoryLocator, offsetOfZip64EOCDRecord: UInt) {
        self.numberOfDiskWithZip64EOCDRecordStart = locator.numberOfDiskWithZip64EOCDRecordStart
        self.relativeOffsetOfZip64EOCDRecord = offsetOfZip64EOCDRecord
        self.totalNumberOfDisk = locator.totalNumberOfDisk
    }
}

extension Archive.Zip64EndOfCentralDirectory {
    var data: Data { record.data + locator.data }
}
