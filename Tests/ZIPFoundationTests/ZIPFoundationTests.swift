//
//  ZIPFoundationTests.swift
//  ZIPFoundation
//
//  Copyright © 2017-2026 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/main/LICENSE for license information.
//

import XCTest
#if canImport(Android)
import Android
#endif
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
        var tempZipDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        tempZipDirectory.appendPathComponent("ZipTempDirectory")
        // Parallel test processes each run setUp() and tearDown() and need their own directory.
        tempZipDirectory.appendPathComponent(ProcessInfo.processInfo.globallyUniqueString)
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
            try fileManager.createDirectory(at: tempZipDirectoryURL, withIntermediateDirectories: true,
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
        var url = ZIPFoundationTests.tempZipDirectoryURL
        url = url.appendingPathComponent(self.pathComponent(for: testFunction), isDirectory: true)
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        } catch {
            XCTFail("Failed to get create directory for test function:\(testFunction)")
            type(of: self).tearDown()
            preconditionFailure()
        }
        return url
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
}
