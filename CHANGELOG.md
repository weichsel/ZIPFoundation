# Changelog

## [0.9.21](https://github.com/weichsel/ZIPFoundation/releases/tag/0.9.21)

### Added
 - Added support for compressed symlinks and symlinks pointing into other subfolders of an archive
 - Added `symlinksValidWithin` parameter to control symlink containment (replaces `allowUncontainedSymlinks`)
 - Added support for symlink modification dates on Linux
 - Added support for the Info-ZIP Unicode Path extra field
 - Added support for building for Windows
 - Added package manifest for Swift 6.4 (Xcode 27)

### Updated
 - Fixed symlink containment bypass via chained relative symlinks
 - Fixed crashes when reading archives with invalid ZIP64 sizes or offsets
 - Fixed endless loop when an entry claims more data than the archive contains
 - Fixed crash when reading past the end of an in-memory archive
 - Fixed endless loop and out-of-bounds read when decoding truncated deflate streams on non-Darwin platforms
 - Fixed reading of ZIP64 archives with entries at offset 0 or a low "version needed to extract"
 - Fixed loss of added entries after removing an entry from an archive that contains ZIP64 entries
 - Fixed memory growth when zipping or unzipping archives with many entries
 - Fixed performance regression when opening archives with many entries
 - Fixed detection of directory entries with a trailing path delimiter
 - Fixed build errors on Android
 - Fixed `pkg-config` warning when building for Apple platforms
 - Fixed deprecation warning in package manifest

## [0.9.20](https://github.com/weichsel/ZIPFoundation/releases/tag/0.9.20)

### Added
 - Added support for file modification date attributes on non-Darwin platforms
 - Added code page 437 string decoding for paths on non-Darwin platforms

### Updated
 - Fixed resource leak in `Archive.makeBackingConfiguration`
 - Fixed memory leak in `Data.readChunk`
 - Fixed memory alignment crash in debug mode
 - Fixed API type reason ID in privacy manifest
 - Improved error handling in `MemoryFile` type
 - Improved `String` to `Data` conversion to use non-optional API
 - Improved error handling for `ftello` operations
 - Improved README examples to use non-deprecated API
 - Improved CI configuration and linting

## [0.9.19](https://github.com/weichsel/ZIPFoundation/releases/tag/0.9.19)

### Updated
 - Fixed privacy manifest
 - Fixed deprecation warning in package manifest
 - Fixed resource bundling instruction in the podspec

## [0.9.18](https://github.com/weichsel/ZIPFoundation/releases/tag/0.9.18)

### Added
 - Added ability to enforce symlink containment

### Updated
 - Fixed path escape vulnerability
 - Fixed platform requirement warnings
 - Improved error info when encountering permission errors

## [0.9.17](https://github.com/weichsel/ZIPFoundation/releases/tag/0.9.17)

### Added
 - Added visionOS support
 - Added Xcode privacy manifest
 - Added throwing initializers for `Archive`
 
### Updated
 - Improved symlink handling
 - Improved forwarding of underlying errors

## [0.9.16](https://github.com/weichsel/ZIPFoundation/releases/tag/0.9.16)

### Added
 - Added `isCompressed` accessor to `Entry`
 
### Updated
 - Improved README and documentation
 - Fixed deprecation in the random test data generator

## [0.9.15](https://github.com/weichsel/ZIPFoundation/releases/tag/0.9.15)

### Added
 - Added initial support for building for Android
 
### Updated
 - Fixed CRC32 calculation for non-final compression streams
 - Fixed evaluation of CRC32 checksums when using `FileManager.unzipItem`

## [0.9.14](https://github.com/weichsel/ZIPFoundation/releases/tag/0.9.14)

### Updated
 - Fixed missing extra field data after entry removal

## [0.9.13](https://github.com/weichsel/ZIPFoundation/releases/tag/0.9.13)

### Added
 - Added large file support (ZIP64)
 
### Updated
 - Fixed an `UInt16` overflow when calculating the number of entries
 - Fixed entry removal for in-memory archives
 - Fixed a crash when `fopen()` fails during archive replacement
 - Improved CRC32 calculation performance via zlib (when available)

## [0.9.12](https://github.com/weichsel/ZIPFoundation/releases/tag/0.9.12)

### Added
 - Added check to disallow removal of entries from readonly archives
 - Added guard against API misuse by providing zero byte buffer sizes
 
### Updated
 - Fixed an `UInt16` overflow when calculating the end of the central directory record
 - Fixed detection of ZIP version required to extract
 - Fixed missing consumer closure call for zero byte entries
 - Fixed erroneous application of `.deflate` compression on `.symlink` and `.directory` entries
 - Improved detection of `.directory` entries
 - Improved performance when looking up entries via subscripting
 - Improved consistency of URL format used in the Swift package description

## [0.9.11](https://github.com/weichsel/ZIPFoundation/releases/tag/0.9.11)

### Added
 - Read/Write support for in-memory archives
 
### Updated
 - Fixed a memory safety issue during (de)compression
 - Fixed dangling pointer warnings when serializing ZIP internal structs to `Data`
 - Fixed missing Swift 5 language version when integrating via CocoaPods
 - Fixed inconsistent usage of the optional `preferredEncoding` parameter during entry addition
 - Improved documentation for compression settings

## [0.9.10](https://github.com/weichsel/ZIPFoundation/releases/tag/0.9.10)

### Added
 - Optional `skipCRC32` parameter to speed up entry reading
 
### Updated
 - Fixed a race condition during archive creation or extraction
 - Fixed an error when trying to add broken symlinks to an archive
 - Fixed an App Store submission issue by updating the product identifier to use reverse DNS notation
 - Improved CRC32 calculation performance
 - Improved entry replacement performance on separate volumes
 - Improved documentation for closure-based writing

## [0.9.9](https://github.com/weichsel/ZIPFoundation/releases/tag/0.9.9)

### Added
 - Swift 5.0 support
 - Optional `preferredEncoding` parameter to explicitly configure an encoding for filepaths
 
### Updated
 - Fixed a library load error related to dylib versioning
 - Fixed a hang during read when decoding small, `.deflate` compressed entries
 - Improved Linux support
 - Improved test suite on non-Darwin platforms

## [0.9.8](https://github.com/weichsel/ZIPFoundation/releases/tag/0.9.8)

### Updated
- Disabled symlink resolution during path traversal checking

## [0.9.7](https://github.com/weichsel/ZIPFoundation/releases/tag/0.9.7)

### Added
 - App extension support
 - Optional `compressionMethod` parameter for `zipItem:`
 
### Updated
 - Fixed a path traversal attack vulnerability
 - Fixed a crash due to wrong error handling after failed `fopen` calls

### Removed
 - Temporarily removed the currently unsupported `.modificationDate` attribute on non-Darwin platforms

## [0.9.6](https://github.com/weichsel/ZIPFoundation/releases/tag/0.9.6)

### Added
 - Swift 4.1 support
 
### Updated
 - Fixed default directory permissions
 - Fixed a compile issue when targeting Linux

## [0.9.5](https://github.com/weichsel/ZIPFoundation/releases/tag/0.9.5)

### Added
 - Progress tracking support
 - Operation cancellation support
 
### Updated
 - Improved performance of CRC32 calculations
 - Improved Linux support
 - Fixed wrong behaviour when using the `shouldKeepParent` flag
 - Fixed a linker error during archive builds when integrating via Carthage

## [0.9.4](https://github.com/weichsel/ZIPFoundation/releases/tag/0.9.4)

### Updated
 - Fixed a wrong setting for `FRAMEWORK_SEARCH_PATHS` that interfered with code signing
 - Added a proper value for `CURRENT_PROJECT_VERSION` to make the framework App Store compliant when using Carthage

## [0.9.3](https://github.com/weichsel/ZIPFoundation/releases/tag/0.9.3)

### Added
 - Carthage support
 
### Updated
 - Improved error handling
 - Made consistent use of Swift's `CocoaError` instead of `NSError`

## [0.9.2](https://github.com/weichsel/ZIPFoundation/releases/tag/0.9.2)

### Updated
 - Changed default POSIX permissions when file attributes are missing
 - Improved docs
 - Fixed a compiler warning when compiling with the latest Xcode 9 beta

## [0.9.1](https://github.com/weichsel/ZIPFoundation/releases/tag/0.9.1)

### Added
 - Optional parameter to skip CRC32 checksum calculation
 
### Updated
 - Tweaked POSIX buffer sizes to improve IO and comrpression performance
 - Improved source readability
 - Refined documentation
 
### Removed
 - Optional parameter skip decompression during entry retrieval
 
## [0.9.0](https://github.com/weichsel/ZIPFoundation/releases/tag/0.9.0)

### Added
 - Initial release of ZIP Foundation.
