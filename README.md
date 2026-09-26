# driveviewer

A native macOS disk map. It scans a drive or folder and shows files and folders as nested shapes sized by allocated disk space. Double-click a folder to zoom into the saved scan. Click to select, Command-click to select several items, and right-click to reveal an item in Finder or move it to Trash.

The menu bar item shows the startup disk's available percentage and can start a drive scan. Drive scans keep a bounded hierarchy in memory. Smaller entries appear as **Other items**.

## Install

Download the universal macOS ZIP from [Releases](https://github.com/treydoe1/driveviewer/releases/latest), unzip it, and move `driveviewer.app` to Applications. It supports macOS 14 or later on Apple Silicon and Intel Macs.

This build is not notarized. If macOS blocks it, try opening it once, then go to System Settings > Privacy & Security and select Open Anyway. See [Apple's instructions](https://support.apple.com/en-us/102445).

## Build

Requires macOS 14 or later and Xcode command-line tools.

```sh
./build-app.sh
open dist/driveviewer.app
```

To run the tests:

```sh
swift test -c release
```

The local build uses an ad hoc signature. Run `./package-release.sh` to make a universal ZIP.

## Access and privacy

driveviewer scans local file metadata. It does not upload file names or scan results, and it has no telemetry or network service. It stores the last selected scan path in macOS user defaults so the next scan can use the same location. It does not store a scan between launches.

For a full drive scan, macOS may require Full Disk Access. The app can open the correct System Settings page, but macOS requires the user to grant access. Moving an item to Trash requires confirmation in the app.

Scan totals use allocated file size. APFS clones, snapshots, and protected system storage can make the total differ from Finder's used-space number. Drive scans skip `~/Library/CloudStorage` to avoid walking remote placeholders; choose that folder directly to scan its local contents. The app reports folders it could not read.

## Contributing

Build the app and run the tests before opening a pull request. Keep scan results and personal files out of commits.

## License

MIT. See [LICENSE](LICENSE).
