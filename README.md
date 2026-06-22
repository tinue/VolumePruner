# VolumePruner

A macOS menu-bar utility that removes hidden Mac metadata files from removable media before you hand it to a non-Mac system.

---

## The Problem

Whenever macOS reads or writes to a volume, it quietly leaves behind hidden metadata files:

| File | Purpose on a Mac |
|---|---|
| `.DS_Store` | Stores Finder window layout and icon positions |
| `._filename` | AppleDouble resource forks for files without native support |
| `.Spotlight-V100` | Spotlight search index |
| `.Trashes` | Per-volume Trash folder |
| `.fseventsd` | File system event log |
| `Thumbs.db`, `desktop.ini` | Windows equivalents created when running on a Mac via virtualization or crossover tools |

On a Mac these files are harmless and invisible. On other systems they cause real problems:

- **Car entertainment systems and GPS devices** fail firmware or map updates when extra files are present on the SD card or USB stick.
- **Cameras and audio recorders** refuse to use a card that contains unexpected directory structures.
- **Retro or embedded systems** display spurious entries for invisible files, or crash when traversing unexpected directories like `.Spotlight-V100`.

---

## The Solution

VolumePruner monitors your removable media and removes these files on demand or automatically whenever a watched volume changes.

---

## What VolumePruner Cleans — and What It Does Not

### Removable media: yes

VolumePruner targets volumes formatted with filesystems commonly used on removable media:

- **FAT32 / MS-DOS** — SD cards, USB sticks, older devices
- **exFAT** — SD cards, USB sticks, modern devices
- **NTFS** — Windows-formatted USB drives and sticks

The key criterion is the filesystem type, not the physical connector. A large external hard drive formatted as exFAT and left permanently on your desk will still appear in the list. The configurable size limit (default 2 TB) is the practical guard against that: drives clearly intended as permanent storage are too large to qualify.

### Permanently attached drives: intentionally excluded by default

Drives you never unplug — a Thunderbolt RAID, a USB-C desktop drive — are not the target. They never need to talk to a car stereo or a camera. The size limit exists precisely for this reason. If you lower it, you take responsibility for what you include.

### APFS volumes: never touched

APFS is Apple's own filesystem, used on every Mac's internal drive and on Apple-formatted external drives. It can only be mounted on a Mac. A non-Mac system will never see an APFS volume, so the metadata files on it are nobody else's problem. VolumePruner does not touch APFS (or its predecessor HFS+) under any circumstances.

### Network shares: intentionally not supported

Modern Windows 10/11 and current Linux kernels automatically filter Mac metadata files when reading SMB/NFS shares — they are simply not shown to users or applications on those systems. The problem that VolumePruner solves does not exist on modern network shares. Cleaning a NAS would require slow recursive traversal over the network, add meaningful complexity, and provide no benefit in practice.

---

## User Guide

### Installation

VolumePruner is a menu-bar application. After launching it, a drive icon appears in your menu bar. The app does not appear in the Dock. To have it start automatically at login, enable **Launch at login** in Settings.

### The Menu

Click the menu-bar icon to open the volume list. Each row shows one eligible mounted volume:

- **Green dot** — no junk files found
- **Orange dot** — junk files are present; the volume is ready to clean
- **Grey dot** — status check still in progress

VolumePruner checks each volume in the background every 10 seconds (configurable). The status shown when you open the menu is the result of the last completed check — opening the menu does not trigger a new scan.

### Cleaning a Volume

| Button | What it does |
|---|---|
| **Clean** | Removes all junk files from the entire volume recursively |
| **Clean & Eject** | Removes junk files, then safely ejects the volume |

The clean operation walks the entire volume tree. On a large SD card with many directories this may take a few seconds. On a small USB stick it is nearly instant.

### Watch Mode

Toggle the **eye icon** on a volume row to enable Watch mode. While a volume is watched, VolumePruner automatically cleans it whenever its contents change — for example, when macOS writes a `.DS_Store` after you browse it in Finder.

Watched volumes are remembered by their hardware identity (volume UUID), not their mount path. If you eject and re-insert an SD card, it will be watched again automatically.

Unmounted watched volumes remain listed in **Settings → Watched Volumes**, so you can review or remove them even when the media is not inserted.

### Full Disk Access

Removing `.Spotlight-V100` requires **Full Disk Access**, because macOS protects that directory at the kernel level regardless of filesystem permissions.

If VolumePruner encounters a permission error cleaning this directory, an orange warning banner appears at the top of the menu. Click **Grant…** to open the relevant Privacy & Security pane, then add VolumePruner to the Full Disk Access list.

All other junk files are removed without Full Disk Access.

### Settings

Open Settings via the button at the bottom of the menu, or with **⌘,** while the menu is open.

| Setting | Description |
|---|---|
| **Launch at login** | Start VolumePruner automatically when you log in |
| **Max volume size** | Volumes larger than this (in GB) are ignored. Default: 2000 GB |
| **Scan interval** | How often the background status check runs, in seconds. Default: 10 s |
| **Watched Volumes** | List of all watched volumes, including currently unmounted ones. Remove entries here |
| **Recent Activity** | Log of the last 50 clean operations with file counts and reclaimed space |

---

## Privacy

VolumePruner does not connect to the internet, does not collect data, and does not send anything anywhere. All operations are local. The only persistent storage is your preferences in `UserDefaults` and, when Full Disk Access is requested, the system's TCC database.
