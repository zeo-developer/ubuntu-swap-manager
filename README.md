# Ubuntu Swap Manager

Interactive Bash script to **create**, **delete**, and **tune** swap (swappiness) on Ubuntu — with automatic `/etc/fstab` & `sysctl` persistence.

```
╔══════════════════════════════════════╗
║        SWAP MANAGER - UBUNTU         ║
╚══════════════════════════════════════╝
 RAM: 1.2Gi/1.9Gi   Swap: 0B/2.0Gi   swappiness: 10

  1. Create swap
  2. Delete swap
  3. Tune swap usage priority (swappiness)
  4. Show swap status
  0. Exit

Select an option [0-4]:
```

## ✨ Features

- 📦 **Create swap file** – suggests a size based on your RAM, checks free disk space, uses `fallocate` (falls back to `dd`)
- 🗑️ **Delete swap** – lists active swaps, disables and removes the selected one
- ⚙️ **Tune swappiness** – presets (10 / 30 / 60) or a custom value, plus optional `vfs_cache_pressure`
- 📊 **Show status** – memory usage, active swaps, current kernel parameters
- 💾 **Persistent** – survives reboot via `/etc/fstab` and `/etc/sysctl.d/99-swap.conf`
- 🛡️ **Safe** – confirmation prompts, automatic `/etc/fstab` backups before any change

## 📋 Requirements

- Ubuntu 18.04 / 20.04 / 22.04 / 24.04 (also works on Debian and most systemd-based distros)
- Bash 4+
- Root privileges (`sudo`)

## 🚀 Quick Start

### Option 1: Run directly (one-liner)

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/zeo-developer/ubuntu-swap-manager/refs/heads/main/swap.sh)"
```

Or with `wget`:

```bash
sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/zeo-developer/ubuntu-swap-manager/refs/heads/main/swap.sh)"
```

> ⚠️ Do **not** use `curl ... | sudo bash` — the script is interactive and needs your keyboard as input.

### Option 2: Download and run

```bash
curl -fsSL -o swap.sh https://raw.githubusercontent.com/zeo-developer/ubuntu-swap-manager/refs/heads/main/swap.sh
chmod +x swap.sh
sudo ./swap.sh
```

### Option 3: Install as a system command

```bash
sudo curl -fsSL -o /usr/local/bin/swap-manager https://raw.githubusercontent.com/zeo-developer/ubuntu-swap-manager/refs/heads/main/swap.sh
sudo chmod +x /usr/local/bin/swap-manager

# Then run anytime with:
sudo swap-manager
```

## 📖 Usage Guide

### 1. Create swap

```
Select an option [0-4]: 1

===== CREATE SWAP =====
[INFO] Current RAM: 1987MB — suggested swap size: 4G
Enter swap size (e.g. 2G, 512M) [4G]: 2G
Swap file path [/swapfile]:
[INFO] Creating 2048MB swap file at /swapfile ...
[OK] Added to /etc/fstab (fstab backed up).
[OK] Swap created successfully!
```

- **Size**: accepts `2G`, `512M`, or a plain number (treated as GB). Press Enter to use the suggested value.
- **Path**: default is `/swapfile`. Press Enter to keep it.
- If the file already exists, you'll be asked whether to overwrite it.

Suggested size:

| RAM        | Suggested swap |
|------------|----------------|
| ≤ 2 GB     | ~2× RAM        |
| 2 – 8 GB   | = RAM          |
| > 8 GB     | 4 GB           |

### 2. Delete swap

```
Select an option [0-4]: 2

===== DELETE SWAP =====
  1. /swapfile file 2G
  0. Cancel
Select swap to delete: 1
Confirm deleting swap /swapfile? [y/N]: y
[INFO] Disabling swap /swapfile ...
[OK] Removed from /etc/fstab (fstab backed up).
[OK] Deleted file /swapfile.
[OK] Swap deletion completed.
```

> ℹ️ If the swap is a **partition**, it is only disabled — the partition itself is never removed.

### 3. Tune swap usage priority (swappiness)

`vm.swappiness` (0–100) controls how aggressively the kernel moves memory pages to swap. **Higher = uses swap more.**

| Value | Recommended for |
|-------|-----------------|
| `10`  | Servers / VPS (prefer RAM, recommended) |
| `30`  | Balanced |
| `60`  | Ubuntu default / desktops |

You can optionally tune `vm.vfs_cache_pressure` (default `100`, recommended `50`) to keep filesystem metadata cached longer.

Settings are applied immediately and saved to `/etc/sysctl.d/99-swap.conf`.

### 4. Show swap status

Displays `free -h`, `swapon --show`, and the current `swappiness` / `vfs_cache_pressure` values.

## 🔍 Manual Verification

```bash
free -h                         # memory & swap usage
swapon --show                   # active swaps
cat /proc/sys/vm/swappiness     # current swappiness
grep swap /etc/fstab            # boot persistence
cat /etc/sysctl.d/99-swap.conf  # persisted kernel params
```

## 🛠️ Troubleshooting

| Problem | Solution |
|---------|----------|
| `This script must be run as root` | Run with `sudo` |
| `swapoff failed` | Not enough free RAM to move swapped data back. Stop some services and retry. |
| `fallocate is not available` | Normal on some filesystems; the script falls back to `dd` automatically. |
| `Not enough disk space` | Free up disk space or choose a smaller size / another path. |
| Broke `/etc/fstab` | Restore from backup: `ls /etc/fstab.bak.*` then `sudo cp /etc/fstab.bak.<timestamp> /etc/fstab` |

> ⚠️ **Btrfs users:** swap files on Btrfs need special handling (no CoW, no compression). Consider using `btrfs filesystem mkswapfile` instead.

## 📄 License

MIT
