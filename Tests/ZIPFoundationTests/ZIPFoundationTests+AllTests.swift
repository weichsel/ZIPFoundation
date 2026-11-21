//
//  ZIPFoundationTests+AllTests.swift
//  ZIPFoundation
//
//  Copyright © 2017-2026 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/main/LICENSE for license information.
//

import XCTest
@testable import ZIPFoundation

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
            ("testArchiveWithTrailingData", testArchiveWithTrailingData),
            ("testRemoveEntryBeforeStoredSymlinkWithWrongSize", testRemoveEntryBeforeStoredSymlinkWithWrongSize),
            ("testRemoveEntryBeforeStoredSymlinkWithDataDescriptor",
             testRemoveEntryBeforeStoredSymlinkWithDataDescriptor),
            ("testRemoveEntryBeforeWrongDataDescriptorSize", testRemoveEntryBeforeWrongDataDescriptorSize),
            ("testExtractStoredFileWithWrongUncompressedSize", testExtractStoredFileWithWrongUncompressedSize),
            ("testReadEntryWithWrongDataDescriptorSizes", testReadEntryWithWrongDataDescriptorSizes),
            ("testUnzipEntryWithWrongDataDescriptor", testUnzipEntryWithWrongDataDescriptor),
            ("testRemoveEntryBeforeUnsignedDataDescriptor", testRemoveEntryBeforeUnsignedDataDescriptor),
            ("testArchiveInvalidDataErrorConditions", testArchiveInvalidDataErrorConditions),
            ("testArchiveIteratorErrorConditions", testArchiveIteratorErrorConditions),
            ("testArchiveReadErrorConditions", testArchiveReadErrorConditions),
            ("testArchiveUpdateErrorConditions", testArchiveUpdateErrorConditions),
            ("testCorruptFileErrorConditions", testCorruptFileErrorConditions),
            ("testCorruptSymbolicLinkErrorConditions", testCorruptSymbolicLinkErrorConditions),
            ("testDecodeThrowsWhenProviderSignalsEOFBeforeStreamEnd",
             testDecodeThrowsWhenProviderSignalsEOFBeforeStreamEnd),
            ("testDecodeChunksSmallerThanBufferSize", testDecodeChunksSmallerThanBufferSize),
            ("testCreateArchiveAddCompressedEntry", testCreateArchiveAddCompressedEntry),
            ("testConsumersCanKeepProcessedData", testConsumersCanKeepProcessedData),
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
            ("testUnzipDirectoryEntryMarkedAsFile", testUnzipDirectoryEntryMarkedAsFile),
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
            ("testSimpleTraversalAttack", testSimpleTraversalAttack),
            ("testPathDelimiterTraversalAttack", testPathDelimiterTraversalAttack),
            ("testUnzipItem", testUnzipItem),
            ("testUnzipItemToRelativeDestination", testUnzipItemToRelativeDestination),
            ("testUnzipItemWithPreferredEncoding", testUnzipItemWithPreferredEncoding),
            ("testUnzipItemErrorConditions", testUnzipItemErrorConditions),
            ("testUnzipUncontainedSymlink", testUnzipUncontainedSymlink),
            ("testUnzipEntryThroughSymlinkToTildeDirectory", testUnzipEntryThroughSymlinkToTildeDirectory),
            ("testUnzipSymlinkWithTildeDestination", testUnzipSymlinkWithTildeDestination),
            ("testUnzipChainedSymlinkTraversal", testUnzipChainedSymlinkTraversal),
            ("testUnzipDeferredSymlinkTraversal", testUnzipDeferredSymlinkTraversal),
            ("testUnzipEntryPathTraversalThroughSymlink", testUnzipEntryPathTraversalThroughSymlink),
            ("testUnzipEntryThroughUncontainedSymlink", testUnzipEntryThroughUncontainedSymlink),
            ("testUnzipEntryThroughContainedSymlink", testUnzipEntryThroughContainedSymlink),
            ("testUnzipSymlinkToNotYetExistingSymlink", testUnzipSymlinkToNotYetExistingSymlink),
            ("testSymlinkContainmentWithUnresolvablePaths", testSymlinkContainmentWithUnresolvablePaths),
            ("testUnzipIntoSymlinkLoop", testUnzipIntoSymlinkLoop),
            ("testContainmentOfAbsolutePaths", testContainmentOfAbsolutePaths),
            ("testUnzipEntryWithParentReference", testUnzipEntryWithParentReference),
            ("testUnzipEntryWithLeadingCombiningMark", testUnzipEntryWithLeadingCombiningMark),
            ("testUnzipEntryIntoDirectoryAlias", testUnzipEntryIntoDirectoryAlias),
            ("testUnzipEntryWithoutName", testUnzipEntryWithoutName),
            ("testUnzipSymlinkWithInvalidDestination", testUnzipSymlinkWithInvalidDestination),
            ("testZipItem", testZipItem),
            ("testLinuxTestSuiteIncludesAllTests", testLinuxTestSuiteIncludesAllTests),
            ("testFileModificationDate", testFileModificationDate),
            ("testFileModificationDateHelperMethods", testFileModificationDateHelperMethods),
            ("testInvalidSymlinkCompressionMethodErrorConditions", testInvalidSymlinkCompressionMethodErrorConditions),
            ("testReadStructureErrorConditions", testReadStructureErrorConditions),
            ("testReadChunkErrorConditions", testReadChunkErrorConditions),
            ("testWriteChunkErrorConditions", testWriteChunkErrorConditions),
            ("testWriteLargeChunkErrorConditions", testWriteLargeChunkErrorConditions),
            ("testUpdatedCentralDirectoryStructureKeepsOtherExtraFields",
             testUpdatedCentralDirectoryStructureKeepsOtherExtraFields),
            ("testUpdatedCentralDirectoryStructureKeepsVersionNeededToExtract",
             testUpdatedCentralDirectoryStructureKeepsVersionNeededToExtract),
            ("testUpdatedCentralDirectoryStructureRemovesUnneededZIP64Field",
             testUpdatedCentralDirectoryStructureRemovesUnneededZIP64Field),
            ("testUpdatedCentralDirectoryStructureWithZeroZIP64Values",
             testUpdatedCentralDirectoryStructureWithZeroZIP64Values),
            ("testUpdatedCentralDirectoryStructureWithExceedingExtraFieldLength",
             testUpdatedCentralDirectoryStructureWithExceedingExtraFieldLength)
        ] + zip64Tests + darwinOnlyTests + posixOnlyTests + swift5OnlyTests
    }

    static var zip64Tests: [(String, (ZIPFoundationTests) -> () throws -> Void)] {
        return [
            ("testZipCompressedZIP64Item", testZipCompressedZIP64Item),
            ("testZipUncompressedZIP64Item", testZipUncompressedZIP64Item),
            ("testUnzipCompressedZIP64Item", testUnzipCompressedZIP64Item),
            ("testUnzipUncompressedZIP64Item", testUnzipUncompressedZIP64Item),
            ("testUnzipItemWithZIP64DataDescriptor", testUnzipItemWithZIP64DataDescriptor),
            ("testReadZIP64ArchiveWithLowVersionNeededToExtract",
             testReadZIP64ArchiveWithLowVersionNeededToExtract),
            ("testEntryZIP64ExtraField", testEntryZIP64ExtraField),
            ("testEntryZIP64FieldOnlyHasUncompressedSize", testEntryZIP64FieldOnlyHasUncompressedSize),
            ("testEntryZIP64FieldIncludingDiskNumberStart", testEntryZIP64FieldIncludingDiskNumberStart),
            ("testEntryValidZIP64DataDescriptor", testEntryValidZIP64DataDescriptor),
            ("testEntryWithZIP64ExtraField", testEntryWithZIP64ExtraField),
            ("testEntryInvalidZIP64ExtraFieldErrorConditions", testEntryInvalidZIP64ExtraFieldErrorConditions),
            ("testEntryScanForZIP64Field", testEntryScanForZIP64Field),
            ("testEntryScanForZIP64FieldErrorConditions", testEntryScanForZIP64FieldErrorConditions),
            ("testEntryZIP64FieldContainingFields", testEntryZIP64FieldContainingFields),
            ("testExtraFieldDataReplacingZIP64Field", testExtraFieldDataReplacingZIP64Field),
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
            ("testRemoveEntryUpdatesSizeOfCentralDirectory", testRemoveEntryUpdatesSizeOfCentralDirectory),
            ("testRemoveEntryWithZIP64ExtendedInformation", testRemoveEntryWithZIP64ExtendedInformation),
            ("testRemoveZIP64EntryPreservesExtraFields", testRemoveZIP64EntryPreservesExtraFields),
            ("testWriteEOCDWithTooLargeSizeOfCentralDirectory", testWriteEOCDWithTooLargeSizeOfCentralDirectory),
            ("testWriteEOCDWithTooLargeCentralDirectoryOffset", testWriteEOCDWithTooLargeCentralDirectoryOffset),
            ("testWriteEOCDWithTooSmallCentralDirectory", testWriteEOCDWithTooSmallCentralDirectory),
            ("testAddEntryWithInvalidZIP64CentralDirectory", testAddEntryWithInvalidZIP64CentralDirectory),
            ("testIterateEntryWithOverflowingZIP64DataDescriptor", testIterateEntryWithOverflowingZIP64DataDescriptor),
            ("testExtractEntryWithInvalidZIP64Size", testExtractEntryWithInvalidZIP64Size),
            ("testExtractCompressedEntryWithInvalidZIP64Size", testExtractCompressedEntryWithInvalidZIP64Size),
            ("testExtractEntryWithInvalidZIP64DataOffset", testExtractEntryWithInvalidZIP64DataOffset),
            ("testUnzipItemWithInvalidZIP64SizeProgress", testUnzipItemWithInvalidZIP64SizeProgress),
            ("testExtractEntryWithZIP64SizeExceedingArchive", testExtractEntryWithZIP64SizeExceedingArchive),
            ("testRemoveEntryWithInvalidZIP64Size", testRemoveEntryWithInvalidZIP64Size),
            ("testRemoveEntryWithReorderedCentralDirectory", testRemoveEntryWithReorderedCentralDirectory),
            ("testRemoveEntryPreservesExtraFields", testRemoveEntryPreservesExtraFields),
            ("testWriteLargeChunk", testWriteLargeChunk),
            ("testExtractUncompressedZIP64Entries", testExtractUncompressedZIP64Entries),
            ("testExtractCompressedZIP64Entries", testExtractCompressedZIP64Entries),
            ("testExtractEntryWithZIP64DataDescriptor", testExtractEntryWithZIP64DataDescriptor),
            ("testIterateZIP64EntryWithDefaultDataDescriptor", testIterateZIP64EntryWithDefaultDataDescriptor),
            ("testRemoveEntryNextToDefaultDataDescriptor", testRemoveEntryNextToDefaultDataDescriptor),
            ("testRemoveEntryNextToWrongDefaultDataDescriptor", testRemoveEntryNextToWrongDefaultDataDescriptor),
            ("testRemoveEntryNextToWrongZIP64DataDescriptor", testRemoveEntryNextToWrongZIP64DataDescriptor),
            ("testUnzipSymlink", testUnzipSymlink),
            ("testAddSymlinkWithInvalidSize", testAddSymlinkWithInvalidSize),
            ("testUnzipCompressedSymlink", testUnzipCompressedSymlink),
            ("testExtractStoredSymlinkWithOversizedLocalHeader", testExtractStoredSymlinkWithOversizedLocalHeader),
            ("testExtractStoredZIP64Symlink", testExtractStoredZIP64Symlink),
            ("testExtractStoredSymlinkWithWrongUncompressedSize", testExtractStoredSymlinkWithWrongUncompressedSize),
            ("testExtractCompressedSymlinkWithSmallBufferSize", testExtractCompressedSymlinkWithSmallBufferSize),
            ("testDeprecatedContainmentCheck", testDeprecatedContainmentCheck)
        ]
    }

    static var darwinOnlyTests: [(String, (ZIPFoundationTests) -> () throws -> Void)] {
        #if os(macOS) || os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
        return [
            ("testZipItemProgress", testZipItemProgress),
            ("testUnzipItemProgress", testUnzipItemProgress),
            ("testConsistentBehaviorWithSystemZIPUtilities", testConsistentBehaviorWithSystemZIPUtilities),
            ("testRemoveEntryProgress", testRemoveEntryProgress),
            ("testReplaceCurrentArchiveWithArchiveCrossLink", testReplaceCurrentArchiveWithArchiveCrossLink),
            ("testArchiveAddUncompressedEntryProgress", testArchiveAddUncompressedEntryProgress),
            ("testArchiveAddCompressedEntryProgress", testArchiveAddCompressedEntryProgress),
            ("testZIP64ArchiveAddEntryProgress", testZIP64ArchiveAddEntryProgress),
            // Relies on Darwin file system behavior and on not running as root
            ("testZipItemErrorConditions", testZipItemErrorConditions),
            // Applying permissions on symlinks is only relevant on Darwin platforms
            ("testSymlinkPermissionsTransferErrorConditions", testSymlinkPermissionsTransferErrorConditions)
        ]
        #else
        return []
        #endif
    }

    static var posixOnlyTests: [(String, (ZIPFoundationTests) -> () throws -> Void)] {
        #if os(macOS) || os(iOS) || os(tvOS) || os(visionOS) || os(watchOS) || os(Linux)
        return [
            ("testSymlinkModificationDateTransferErrorConditions", testSymlinkModificationDateTransferErrorConditions)
        ]
        #else
        return []
        #endif
    }

    static var swift5OnlyTests: [(String, (ZIPFoundationTests) -> () throws -> Void)] {
        #if swift(>=5.0) && (os(macOS) || os(iOS) || os(tvOS) || os(visionOS) || os(watchOS) || os(Linux))
        return [
            ("testCreateArchiveAddUncompressedEntryToMemory", testCreateArchiveAddUncompressedEntryToMemory),
            ("testCreateArchiveAddCompressedEntryToMemory", testCreateArchiveAddCompressedEntryToMemory),
            ("testUpdateArchiveRemoveUncompressedEntryFromMemory", testUpdateArchiveRemoveUncompressedEntryFromMemory),
            ("testExtractCompressedFolderEntriesFromMemory", testExtractCompressedFolderEntriesFromMemory),
            ("testExtractUncompressedFolderEntriesFromMemory", testExtractUncompressedFolderEntriesFromMemory),
            ("testMemoryArchiveErrorConditions", testMemoryArchiveErrorConditions),
            ("testMemoryArchiveWithInvalidLocalHeaderOffset", testMemoryArchiveWithInvalidLocalHeaderOffset),
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
