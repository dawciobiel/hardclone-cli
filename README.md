# hardclone-cli

**hardclone-cli** is a lightweight, interactive Bash-based tool for creating full disk/partition images via terminal — ideal for remote or SSH-based usage. It supports compression, optional encryption, image splitting, verification, and checksum generation.

## Features

- Interactive CLI interface
- Lists available disks and partitions
- Supports popular compression formats:
  - `gzip`
  - `zstd`
  - `bzip2`
  - `xz`
- Optional GPG encryption (with interactive passphrase prompt)
- Optional image splitting into 2GB chunks
- Optional verification (`cmp`) against source
- Optional hash generation (SHA256 + MD5)

## Requirements

- `bash`
- `dd`
- `lsblk`
- Compression tools: `gzip`, `zstd`, `bzip2`, `xz` (as selected)
- Optional: `gpg`, `cmp`, `sha256sum`, `md5sum`, `split`

## Usage

Simply run the script from the terminal:

```bash
chmod +x hardclone-cli.sh
./hardclone-cli.sh
```

You will be guided step-by-step through:

1. Selecting a disk and partition
2. Naming the output image file
3. Choosing compression and encryption
4. (Optional) Enabling image split, verify, and checksum options

### Example session:

```
--------------------------------------------------------------------------------------------

Available disks:
1    sda  512G  Samsung SSD
2    sdb  2T    WDC WD20EZRZ

--------------------------------------------------------------------------------------------

Select disk number: 2

--------------------------------------------------------------------------------------------

Selected disk: /dev/sdb

Available partitions on /dev/sdb:
1)  /dev/sdb1   1T
2)  /dev/sdb2   1T

--------------------------------------------------------------------------------------------

Select partition number: 1

--------------------------------------------------------------------------------------------

Selected partition: sdb1

Enter filename for the image: backup_july2025

--------------------------------------------------------------------------------------------

Enable encryption with GPG?
1) Yes
2) No
#? 1

--------------------------------------------------------------------------------------------

Select compression method:
1) none
2) gzip
3) zstd
4) bzip2
5) xz
#? 3

--------------------------------------------------------------------------------------------

Do you want to split the image?
1) Yes
2) No
#? 2

--------------------------------------------------------------------------------------------

Do you want to verify the image?
1) Yes
2) No
#? 1

--------------------------------------------------------------------------------------------

Do you want to create checksums (SHA256, MD5)?
1) Yes
2) No
#? 1

--------------------------------------------------------------------------------------------

Creating image of sdb1...
Executing: dd if=/dev/sdb1 bs=4M status=progress | zstd | gpg --symmetric --cipher-algo AES256 > "/tmp/backup_july2025.img.zst.gpg"

--------------------------------------------------------------------------------------------

Splitting skipped (user chose No).

--------------------------------------------------------------------------------------------

Verifying image...
Verification completed.

--------------------------------------------------------------------------------------------

Generating checksums...
Checksums saved to:
/tmp/backup_july2025.img.zst.gpg.sha256
/tmp/backup_july2025.img.zst.gpg.md5

--------------------------------------------------------------------------------------------

Done.
```

## Output

The resulting image will be stored in `/tmp` by default (or the directory set in the script). Depending on options, files might look like:

```
/tmp/backup_july2025.img.zst.gpg
/tmp/backup_july2025.img.zst.gpg.sha256
/tmp/backup_july2025.img.zst.gpg.md5
```

If split was selected:

```
/tmp/backup_july2025.img.zst.gpg.part_aa
/tmp/backup_july2025.img.zst.gpg.part_ab
...
```

## License

MIT License

## Disclaimer

Use this tool at your own risk. It operates at a low level (`dd`) and can overwrite or misread data if misused. Always double-check the selected disk/partition before proceeding.

---

## Author

**Dawid Bielecki - dawciobiel**
GitHub: [https://github.com/dawciobiel/hardclone-cli](https://github.com/dawciobiel/hardclone-cli)
