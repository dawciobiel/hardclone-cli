# Hardclone CLI

**Interactive partition backup creator with encryption, compression, and file splitting**

<img width="660" height="359" alt="image" src="https://github.com/user-attachments/assets/69d5aa38-ecc8-4bc8-bafb-f5f21cf6b20a" />


![Version](https://img.shields.io/badge/version-v2.0.0-blue) ![License](https://img.shields.io/badge/license-GPL--3.0-green) ![Python](https://img.shields.io/badge/python-3.6+-blue) ![Platform](https://img.shields.io/badge/platform-Linux-lightgrey)

## 📖 Description

Hardclone CLI is an interactive Python script that provides a user-friendly dialog interface for creating partition backups with advanced features like encryption, compression, and file splitting. Built for Linux systems, it uses the powerful `dd` command with additional processing pipelines to create secure and efficient backups.

## ✨ Features

- 🖥️ **Interactive Dialog Interface** - Easy-to-use text-based UI
- 💾 **Smart Device Detection** - Automatically discovers storage devices and partitions
- 🔒 **AES-256-CBC Encryption** - Secure your backups with strong encryption
- 🗜️ **Gzip Compression** - Reduce backup file sizes
- ✂️ **File Splitting** - Split large backups into manageable chunks
- 📊 **Space Validation** - Checks available disk space before backup
- 🔧 **Multiple Detection Methods** - Robust device discovery with fallbacks
- 🚀 **Progress Feedback** - Visual feedback during backup operations

## 📋 Requirements

### System Requirements

- **OS**: Linux (any modern distribution)
- **Python**: 3.6 or higher
- **Privileges**: Root access required

### Python Dependencies

```bash
pip3 install pythondialog
```

### System Tools

The following tools should be available (usually pre-installed):

- `dd` - For creating disk images
- `lsblk` - For listing storage devices
- `blockdev` - For getting device information
- `openssl` - For encryption (optional)
- `gzip` - For compression (optional)
- `split` - For file splitting (optional)

## 🚀 Installation

1. **Clone the repository:**

   ```bash
   git clone https://github.com/dawciobiel/hardclone-cli.git
   cd cli
   ```

2. **Install dependencies:**

   ```bash
   pip3 install pythondialog
   ```

3. **Make executable:**

   ```bash
   chmod +x hcli.py
   ```

## 📖 Usage

**Run as root:**

```bash
sudo python3 hcli.py
```

### Step-by-Step Process

1. **Device Selection** - Choose source storage device
2. **Partition Selection** - Select specific partition to backup
3. **Output Path** - Specify destination for backup file
4. **Encryption** - Optionally encrypt with password
5. **Compression** - Optionally compress to save space
6. **File Splitting** - Optionally split into smaller files
7. **Summary Review** - Confirm operation details
8. **Backup Creation** - Automated backup process

### Example Output Files

Depending on your choices, output files will be named:

- **Plain**: `backup_sda1.img`
- **Compressed**: `backup_sda1.img.gz`
- **Encrypted**: `backup_sda1.img.enc`
- **Compressed + Encrypted**: `backup_sda1.img.gz.enc`
- **Split**: `backup_sda1.img.aa`, `backup_sda1.img.ab`, etc.

## 🔧 Features Details

### Device Detection

The script uses multiple methods to detect storage devices:

1. `lsblk -d` for direct device listing
2. `lsblk` with parent filtering for comprehensive detection
3. `/proc/partitions` parsing as fallback
4. Direct `/dev/` scanning for maximum compatibility

### Supported File Formats

- **Sizes**: K, M, G, T (e.g., `1G`, `500M`, `2048K`)
- **Encryption**: AES-256-CBC with PBKDF2
- **Compression**: Gzip format

### Security Features

- Password confirmation for encryption
- No password storage in memory after use
- Secure OpenSSL encryption parameters

## 📁 File Structure

```
cli/
├── hcli.py              # Main script
├── VERSION             # Version file (auto-generated)
├── README.md           # This file
└── LICENSE             # GPL-3.0 license
```

## ⚠️ Important Notes

- **Always run as root** - Required for low-level disk access
- **Backup critical data** - Test on non-critical systems first
- **Check disk space** - Ensure sufficient space for backups
- **Verify backups** - Always verify backup integrity after creation
- **Keep passwords safe** - Store encryption passwords securely

## 🔄 Restoring Backups

### Plain Image

```bash
sudo dd if=backup_sda1.img of=/dev/sda1 bs=1M
```

### Compressed Image

```bash
gunzip -c backup_sda1.img.gz | sudo dd of=/dev/sda1 bs=1M
```

### Encrypted Image

```bash
openssl enc -d -aes-256-cbc -pbkdf2 -in backup_sda1.img.enc | sudo dd of=/dev/sda1 bs=1M
```

### Split Files

```bash
# First, combine split files
cat backup_sda1.img.* > backup_sda1.img
# Then restore as plain image
sudo dd if=backup_sda1.img of=/dev/sda1 bs=1M
```

## 🐛 Troubleshooting

### Common Issues

**"No storage devices found"**

- Ensure you're running as root
- Check if devices are properly connected
- Verify `lsblk` command works manually

**"python3-dialog module not installed"**

```bash
pip3 install pythondialog
# or
sudo apt-get install python3-dialog
```

**"This script must be run as root"**

```bash
sudo python3 hcli.py
```

**Backup fails with "No space left on device"**

- Check available disk space with `df -h`
- Choose a destination with sufficient space
- Consider using compression to reduce file size

## 📝 Version History

- **v2.0.0** - Enhanced device detection, improved UI, better error handling
- **v1.x.x** - Initial release with basic functionality

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the GPL-3.0 License - see the LICENSE file for details.

## 👨‍💻 Author

**Dawid Bielecki "dawciobiel"**

## 👨‍💻 Beta testers

[AlphaOneWhiskeyFour](<https://github.com/AlphaOneWhiskeyFour>)

## ⭐ Support

If you find this tool useful, please consider giving it a star on GitHub!

------

**⚠️ Disclaimer**: This tool performs low-level disk operations. Always backup important data before use. The author is not responsible for any data loss.
