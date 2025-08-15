## [v0.1.0] - 2025-07-23
### Added
- New feature: Restoring a disk image from file to target partition using `--restore` option.
- Automatic handling of compressed and encrypted image formats (`.gz`, `.xz`, `.zst`, `.aes256`, etc.).
- Input validation for target devices and image file existence.
- Informative progress output during restore operations.

### Changed
- Refactored command-line argument parser for better extensibility.

### Notes
- Compatible image formats follow the documented [Image Naming Scheme](../docs/image-naming-scheme/image-naming-scheme.md).
- The restore functionality is available in the `hardclone-cli-v0.1.0.sh` script version.
