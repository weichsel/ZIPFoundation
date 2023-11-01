//
//  ZIPFoundationTests.swift
//  ZIPFoundation
//
//  Copyright © 2017-2023 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
//

import XCTest
@testable import ZIPFoundation

enum AdditionalDataError: Error {
    case encodingError
    case invalidDataError
}

class ZIPFoundationTests: XCTestCase {
    class var testBundle: Bundle {
        return Bundle(for: self)
    }

    static var tempZipDirectoryURL: URL = {
        let processInfo = ProcessInfo.processInfo
        var tempZipDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        tempZipDirectory.appendPathComponent("ZipTempDirectory")
        // We use a unique path to support parallel test runs via
        // "swift test --parallel"
        // When using --parallel, setUp() and tearDown() are called 
        // multiple times.
        tempZipDirectory.appendPathComponent(processInfo.globallyUniqueString)
        return tempZipDirectory
    }()

    static var resourceDirectoryURL: URL {
        var resourceDirectoryURL = URL(fileURLWithPath: #file)
        resourceDirectoryURL.deleteLastPathComponent()
        resourceDirectoryURL.appendPathComponent("Resources")
        return resourceDirectoryURL
    }

    override class func setUp() {
        super.setUp()
        do {
            let fileManager = FileManager()
            if fileManager.itemExists(at: tempZipDirectoryURL) {
                try fileManager.removeItem(at: tempZipDirectoryURL)
            }
            try fileManager.createDirectory(at: tempZipDirectoryURL,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
        } catch {
            XCTFail("Unexpected error while trying to set up test resources.")
        }
    }

    override class func tearDown() {
        do {
            let fileManager = FileManager()
            try fileManager.removeItem(at: tempZipDirectoryURL)
        } catch {
            XCTFail("Unexpected error while trying to clean up test resources.")
        }
        super.tearDown()
    }

    // MARK: - Helpers

    func archive(for testFunction: String, mode: Archive.AccessMode,
                 preferredEncoding: String.Encoding? = nil) -> Archive {
        var sourceArchiveURL = ZIPFoundationTests.resourceDirectoryURL
        sourceArchiveURL.appendPathComponent(testFunction.replacingOccurrences(of: "()", with: ""))
        sourceArchiveURL.appendPathExtension("zip")
        var destinationArchiveURL = ZIPFoundationTests.tempZipDirectoryURL
        destinationArchiveURL.appendPathComponent(ProcessInfo.processInfo.globallyUniqueString)
        destinationArchiveURL.appendPathExtension("zip")
        do {
            if mode != .create {
                let fileManager = FileManager()
                try fileManager.copyItem(at: sourceArchiveURL, to: destinationArchiveURL)
            }
            let archive = try Archive(url: destinationArchiveURL, accessMode: mode,
                                      pathEncoding: preferredEncoding)
            return archive
        } catch {
            XCTFail("Failed to get test archive: \(error)")
            type(of: self).tearDown()
            preconditionFailure()
        }
    }

    func pathComponent(for testFunction: String) -> String {
        return testFunction.replacingOccurrences(of: "()", with: "")
    }

    func archiveName(for testFunction: String, suffix: String = "") -> String {
        let archiveName = testFunction.replacingOccurrences(of: "()", with: "")
        return archiveName.appending(suffix).appending(".zip")
    }

    func resourceURL(for testFunction: String, pathExtension: String) -> URL {
        var sourceAssetURL = ZIPFoundationTests.resourceDirectoryURL
        sourceAssetURL.appendPathComponent(testFunction.replacingOccurrences(of: "()", with: ""))
        sourceAssetURL.appendPathExtension(pathExtension)
        var destinationAssetURL = ZIPFoundationTests.tempZipDirectoryURL
        destinationAssetURL.appendPathComponent(sourceAssetURL.lastPathComponent)
        do {
            let fileManager = FileManager()
            try fileManager.copyItem(at: sourceAssetURL, to: destinationAssetURL)
            return destinationAssetURL
        } catch {
            XCTFail("Failed to get test resource '\(destinationAssetURL.lastPathComponent)'")
            type(of: self).tearDown()
            preconditionFailure()
        }
    }

    func createDirectory(for testFunction: String) -> URL {
        let fileManager = FileManager()
        var URL = ZIPFoundationTests.tempZipDirectoryURL
        URL = URL.appendingPathComponent(self.pathComponent(for: testFunction))
        do {
            try fileManager.createDirectory(at: URL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            XCTFail("Failed to get create directory for test function:\(testFunction)")
            type(of: self).tearDown()
            preconditionFailure()
        }
        return URL
    }

    func runWithUnprivilegedGroup(handler: () throws -> Void) {
        let originalGID = getgid()
        defer { setgid(originalGID) }
        guard let user = getpwnam("nobody") else { return }

        let gid = user.pointee.pw_gid
        guard 0 == setgid(gid) else { return }
    }

    func runWithFileDescriptorLimit(_ limit: UInt64, handler: () throws -> Void) rethrows {
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS) || os(visionOS) || os(Android)
        let fileNoFlag = RLIMIT_NOFILE
        #else
        let fileNoFlag = Int32(RLIMIT_NOFILE.rawValue)
        #endif
        var storedRlimit = rlimit()
        getrlimit(fileNoFlag, &storedRlimit)
        var tempRlimit = storedRlimit
        tempRlimit.rlim_cur = rlim_t(limit)
        setrlimit(fileNoFlag, &tempRlimit)
        defer { setrlimit(fileNoFlag, &storedRlimit) }
        try handler()
    }

    func runWithoutMemory(handler: () -> Void) {
        #if os(macOS) || os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
        let systemAllocator = CFAllocatorGetDefault().takeUnretainedValue()
        CFAllocatorSetDefault(kCFAllocatorNull)
        defer { CFAllocatorSetDefault(systemAllocator) }
        handler()
        #endif
    }

    // MARK: - ZIP64 Helpers

    // It's not practical to create compressed files that exceed the size limit every time for test,
    // so provide helper methods to mock the maximum size limit

    func mockIntMaxValues(int32Factor: Int = 64, int16Factor: Int = 64) {
        maxUInt32 = UInt32(int32Factor * int32Factor)
        maxUInt16 = UInt16(int16Factor)
    }

    func resetIntMaxValues() {
        maxUInt32 = .max
        maxUInt16 = .max
    }
}

extension ZIPFoundationTests {
    // From https://oleb.net/blog/2017/03/keeping-xctest-in-sync/
    func testLinuxTestSuiteIncludesAllTests() {
        #if os(macOS) || os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
            let thisClass = type(of: self)
            let linuxCount = thisClass.allTests.count
            let darwinCount = Int(thisClass.defaultTestSuite.testCaseCount)
            XCTAssertEqual(linuxCount, darwinCount,
                           "\(darwinCount - linuxCount) tests are missing from allTests")
        #endif
    }

    static var allTests: [(String, (ZIPFoundationTests) -> () throws -> Void)] {
        return [
            ("testArchiveAddEntryErrorConditions", testArchiveAddEntryErrorConditions),
            ("testArchiveCreateErrorConditions", testArchiveCreateErrorConditions),
            ("testArchiveInvalidEOCDRecordConditions", testArchiveInvalidEOCDRecordConditions),
            ("testArchiveInvalidDataErrorConditions", testArchiveInvalidDataErrorConditions),
            ("testArchiveIteratorErrorConditions", testArchiveIteratorErrorConditions),
            ("testArchiveReadErrorConditions", testArchiveReadErrorConditions),
            ("testArchiveUpdateErrorConditions", testArchiveUpdateErrorConditions),
            ("testCorruptFileErrorConditions", testCorruptFileErrorConditions),
            ("testCorruptSymbolicLinkErrorConditions", testCorruptSymbolicLinkErrorConditions),
            ("testCreateArchiveAddCompressedEntry", testCreateArchiveAddCompressedEntry),
            ("testCRC32Calculation", testCRC32Calculation),
            ("testCreateArchiveAddDirectory", testCreateArchiveAddDirectory),
            ("testCreateArchiveAddEntryErrorConditions", testCreateArchiveAddEntryErrorConditions),
            ("testCreateArchiveAddZeroSizeUncompressedEntry", testCreateArchiveAddZeroSizeUncompressedEntry),
            ("testCreateArchiveAddZeroSizeCompressedEntry", testCreateArchiveAddZeroSizeCompressedEntry),
            ("testCreateArchiveAddLargeCompressedEntry", testCreateArchiveAddLargeCompressedEntry),
            ("testCreateArchiveAddLargeUncompressedEntry", testCreateArchiveAddLargeUncompressedEntry),
            ("testCreateArchiveAddSymbolicLink", testCreateArchiveAddSymbolicLink),
            ("testCreateArchiveAddUncompressedEntry", testCreateArchiveAddUncompressedEntry),
            ("testDetectEntryType", testDetectEntryType),
            ("testExtractInvalidBufferSizeErrorConditions", testExtractInvalidBufferSizeErrorConditions),
            ("testDirectoryCreationHelperMethods", testDirectoryCreationHelperMethods),
            ("testEntryIsCompressed", testEntryIsCompressed),
            ("testEntryInvalidAdditionalDataErrorConditions", testEntryInvalidAdditionalDataErrorConditions),
            ("testEntryInvalidPathEncodingErrorConditions", testEntryInvalidPathEncodingErrorConditions),
            ("testEntryInvalidSignatureErrorConditions", testEntryInvalidSignatureErrorConditions),
            ("testEntryMissingDataDescriptorErrorCondition", testEntryMissingDataDescriptorErrorCondition),
            ("testEntryTypeDetectionHeuristics", testEntryTypeDetectionHeuristics),
            ("testEntryValidDataDescriptor", testEntryValidDataDescriptor),
            ("testEntryWrongDataLengthErrorConditions", testEntryWrongDataLengthErrorConditions),
            ("testExtractCompressedDataDescriptorArchive", testExtractCompressedDataDescriptorArchive),
            ("testExtractCompressedFolderEntries", testExtractCompressedFolderEntries),
            ("testExtractEncryptedArchiveErrorConditions", testExtractEncryptedArchiveErrorConditions),
            ("testExtractUncompressedEntryCancelation", testExtractUncompressedEntryCancelation),
            ("testExtractCompressedEntryCancelation", testExtractCompressedEntryCancelation),
            ("testExtractErrorConditions", testExtractErrorConditions),
            ("testExtractPreferredEncoding", testExtractPreferredEncoding),
            ("testExtractMSDOSArchive", testExtractMSDOSArchive),
            ("testExtractUncompressedDataDescriptorArchive", testExtractUncompressedDataDescriptorArchive),
            ("testExtractUncompressedFolderEntries", testExtractUncompressedFolderEntries),
            ("testExtractUncompressedEmptyFile", testExtractUncompressedEmptyFile),
            ("testFileAttributeHelperMethods", testFileAttributeHelperMethods),
            ("testFilePermissionHelperMethods", testFilePermissionHelperMethods),
            ("testFileSizeHelperMethods", testFileSizeHelperMethods),
            ("testFileTypeHelperMethods", testFileTypeHelperMethods),
            ("testInvalidCompressionMethodErrorConditions", testInvalidCompressionMethodErrorConditions),
            ("testInvalidPOSIXError", testInvalidPOSIXError),
            ("testPerformanceReadCompressed", testPerformanceReadCompressed),
            ("testPerformanceReadUncompressed", testPerformanceReadUncompressed),
            ("testPerformanceWriteCompressed", testPerformanceWriteCompressed),
            ("testPerformanceWriteUncompressed", testPerformanceWriteUncompressed),
            ("testPerformanceCRC32", testPerformanceCRC32),
            ("testPOSIXPermissions", testPOSIXPermissions),
            ("testCRC32Check", testCRC32Check),
            ("testProgressHelpers", testProgressHelpers),
            ("testRemoveCompressedEntry", testRemoveCompressedEntry),
            ("testRemoveDataDescriptorCompressedEntry", testRemoveDataDescriptorCompressedEntry),
            ("testRemoveEntryErrorConditions", testRemoveEntryErrorConditions),
            ("testRemoveUncompressedEntry", testRemoveUncompressedEntry),
            ("testTemporaryReplacementDirectoryURL", testTemporaryReplacementDirectoryURL),
            ("testTraversalAttack", testTraversalAttack),
            ("testUnzipItem", testUnzipItem),
            ("testUnzipItemWithPreferredEncoding", testUnzipItemWithPreferredEncoding),
            ("testUnzipItemErrorConditions", testUnzipItemErrorConditions),
            ("testZipItem", testZipItem),
            ("testLinuxTestSuiteIncludesAllTests", testLinuxTestSuiteIncludesAllTests)
        ] + zip64Tests + darwinOnlyTests + swift5OnlyTests
    }

    static var zip64Tests: [(String, (ZIPFoundationTests) -> () throws -> Void)] {
        return [
            ("testZipCompressedZIP64Item", testZipCompressedZIP64Item),
            ("testZipUncompressedZIP64Item", testZipUncompressedZIP64Item),
            ("testUnzipCompressedZIP64Item", testUnzipCompressedZIP64Item),
            ("testUnzipUncompressedZIP64Item", testUnzipUncompressedZIP64Item),
            ("testUnzipItemWithZIP64DataDescriptor", testUnzipItemWithZIP64DataDescriptor),
            ("testEntryZIP64ExtraField", testEntryZIP64ExtraField),
            ("testEntryZIP64FieldOnlyHasUncompressedSize", testEntryZIP64FieldOnlyHasUncompressedSize),
            ("testEntryZIP64FieldIncludingDiskNumberStart", testEntryZIP64FieldIncludingDiskNumberStart),
            ("testEntryValidZIP64DataDescriptor", testEntryValidZIP64DataDescriptor),
            ("testEntryWithZIP64ExtraField", testEntryWithZIP64ExtraField),
            ("testEntryInvalidZIP64ExtraFieldErrorConditions", testEntryInvalidZIP64ExtraFieldErrorConditions),
            ("testEntryScanForZIP64Field", testEntryScanForZIP64Field),
            ("testEntryScanForZIP64FieldErrorConditions", testEntryScanForZIP64FieldErrorConditions),
            ("testArchiveZIP64EOCDRecord", testArchiveZIP64EOCDRecord),
            ("testArchiveInvalidZIP64EOCERecordConditions", testArchiveInvalidZIP64EOCERecordConditions),
            ("testArchiveZIP64EOCDLocator", testArchiveZIP64EOCDLocator),
            ("testArchiveInvalidZIP64EOCDLocatorConditions", testArchiveInvalidZIP64EOCDLocatorConditions),
            ("testCreateZIP64ArchiveWithLargeSize", testCreateZIP64ArchiveWithLargeSize),
            ("testCreateZIP64ArchiveWithTooManyEntries", testCreateZIP64ArchiveWithTooManyEntries),
            ("testAddEntryToArchiveWithZIP64LFHOffset", testAddEntryToArchiveWithZIP64LFHOffset),
            ("testAddDirectoryToArchiveWithZIP64LFHOffset", testAddDirectoryToArchiveWithZIP64LFHOffset),
            ("testCreateZIP64ArchiveWithLargeSizeOfCD", testCreateZIP64ArchiveWithLargeSizeOfCD),
            ("testRemoveEntryFromArchiveWithZIP64EOCD", testRemoveEntryFromArchiveWithZIP64EOCD),
            ("testRemoveZIP64EntryFromArchiveWithZIP64EOCD", testRemoveZIP64EntryFromArchiveWithZIP64EOCD),
            ("testRemoveEntryWithZIP64ExtendedInformation", testRemoveEntryWithZIP64ExtendedInformation),
            ("testWriteEOCDWithTooLargeSizeOfCentralDirectory", testWriteEOCDWithTooLargeSizeOfCentralDirectory),
            ("testWriteEOCDWithTooLargeCentralDirectoryOffset", testWriteEOCDWithTooLargeCentralDirectoryOffset),
            ("testWriteLargeChunk", testWriteLargeChunk),
            ("testExtractUncompressedZIP64Entries", testExtractUncompressedZIP64Entries),
            ("testExtractCompressedZIP64Entries", testExtractCompressedZIP64Entries),
            ("testExtractEntryWithZIP64DataDescriptor", testExtractEntryWithZIP64DataDescriptor)
        ]
    }

    static var darwinOnlyTests: [(String, (ZIPFoundationTests) -> () throws -> Void)] {
        #if os(macOS) || os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
        return [
            ("testFileModificationDate", testFileModificationDate),
            ("testFileModificationDateHelperMethods", testFileModificationDateHelperMethods),
            ("testZipItemProgress", testZipItemProgress),
            ("testUnzipItemProgress", testUnzipItemProgress),
            ("testConsistentBehaviorWithSystemZIPUtilities", testConsistentBehaviorWithSystemZIPUtilities),
            ("testRemoveEntryProgress", testRemoveEntryProgress),
            ("testReplaceCurrentArchiveWithArchiveCrossLink", testReplaceCurrentArchiveWithArchiveCrossLink),
            ("testArchiveAddUncompressedEntryProgress", testArchiveAddUncompressedEntryProgress),
            ("testArchiveAddCompressedEntryProgress", testArchiveAddCompressedEntryProgress),
            ("testZIP64ArchiveAddEntryProgress", testZIP64ArchiveAddEntryProgress),
            // The below test cases test error code paths but they lead to undefined behavior and memory
            // corruption on non-Darwin platforms. We disable them for now.
            ("testReadStructureErrorConditions", testReadStructureErrorConditions),
            ("testReadChunkErrorConditions", testReadChunkErrorConditions),
            ("testWriteChunkErrorConditions", testWriteChunkErrorConditions),
            ("testWriteLargeChunkErrorConditions", testWriteLargeChunkErrorConditions),
            // Fails for Swift < 4.2 on Linux. We can re-enable that when we drop Swift 4.x support
            ("testZipItemErrorConditions", testZipItemErrorConditions),
            // Applying permissions on symlinks is only relevant on Darwin platforms
            ("testSymlinkPermissionsTransferErrorConditions", testSymlinkPermissionsTransferErrorConditions),
            // Applying file modification dates is currently unsupported in corelibs Foundation
            ("testSymlinkModificationDateTransferErrorConditions", testSymlinkModificationDateTransferErrorConditions)
        ]
        #else
        return []
        #endif
    }

    static var swift5OnlyTests: [(String, (ZIPFoundationTests) -> () throws -> Void)] {
        #if swift(>=5.0)
        return [
            ("testAppendFile", testAppendFile),
            ("testCreateArchiveAddUncompressedEntryToMemory", testCreateArchiveAddUncompressedEntryToMemory),
            ("testCreateArchiveAddCompressedEntryToMemory", testCreateArchiveAddCompressedEntryToMemory),
            ("testUpdateArchiveRemoveUncompressedEntryFromMemory", testUpdateArchiveRemoveUncompressedEntryFromMemory),
            ("testExtractCompressedFolderEntriesFromMemory", testExtractCompressedFolderEntriesFromMemory),
            ("testExtractUncompressedFolderEntriesFromMemory", testExtractUncompressedFolderEntriesFromMemory),
            ("testMemoryArchiveErrorConditions", testMemoryArchiveErrorConditions),
            ("testWriteOnlyFile", testWriteOnlyFile),
            ("testReadOnlyFile", testReadOnlyFile),
            ("testReadOnlySlicedFile", testReadOnlySlicedFile),
            ("testReadWriteFile", testReadWriteFile)
        ]
        #else
        return []
        #endif
    }
}

extension Archive {
    func checkIntegrity() -> Bool {
        var isCorrect = false
        do {
            for entry in self {
                let checksum = try self.extract(entry, consumer: { _ in })
                isCorrect = checksum == entry.checksum
                guard isCorrect else { break }
            }
        } catch { return false }
        return isCorrect
    }
}

extension Data {
    static func makeRandomData(size: Int) -> Data {
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
        let bytes = [UInt32](repeating: 0, count: size).map { _ in UInt32.random(in: 0...UInt32.max) }
        #else
        let bytes = [UInt32](repeating: 0, count: size).map { _ in random() }
        #endif
        return Data(bytes: bytes, count: size)
    }
}

#if os(macOS)
extension NSUserScriptTask {
    static func makeVolumeCreationTask(at tempDir: URL, volumeName: String) throws -> NSUserScriptTask {
        let scriptURL = tempDir.appendingPathComponent("createVol.sh", isDirectory: false)
        let dmgURL = tempDir.appendingPathComponent(volumeName).appendingPathExtension("dmg")
        let script = """
        #!/bin/bash
        hdiutil create -size 5m -fs HFS+ -type SPARSEBUNDLE -ov -volname "\(volumeName)" "\(dmgURL.path)"
        hdiutil attach -nobrowse "\(dmgURL.appendingPathExtension("sparsebundle").path)"
        """
        try script.write(to: scriptURL, atomically: false, encoding: .utf8)
        let permissions = NSNumber(value: Int16(0o770))
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: scriptURL.path)
        return try NSUserScriptTask(url: scriptURL)
    }
}
#endif
