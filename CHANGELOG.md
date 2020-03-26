# Changelog

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
