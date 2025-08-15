## [v2.0.0] - 2025-08-15
### Added
- New Python-based CLI (`hcli.py`) with a `dialog` interface for interactive partition backup creation.
- Interactive selection of device, partition, and output path.
- Option to enable encryption (AES-256-CBC) with password entry.
- Option to compress the image (gzip).
- Option to split the resulting file into smaller parts.
- Automatic version detection from the `VERSION` file or Git tags.
- Launch scripts (`launch.sh`, `launch.fish`, `setup.sh`, `bump_version.sh`) and `requirements.txt` for easier setup.

### Changed
- Migration from the Bash-based version (`hardclone-cli-v0.1.0.sh`) to a Python implementation.
- Improved error handling and user input validation.
- Status and progress messages displayed using `dialog`.

### Removed
- Legacy Bash CLI version with manual argument parsing.

### Notes
- Version 2.0.0 requires `python3-dialog` and must be run with root privileges.
- Restore functionality will be added in a future release of the Python CLI.


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
