# usb-blacklist-watcher-pve

Debian package for **Proxmox VE** nodes that prevents specific host USB devices from being passed through to QEMU virtual machines — neither manually via GUI or CLI, nor to already running VMs.

---

## How it works

The package installs two components:

1. **`usb-blacklist-select`** (alias: `usb-blacklist-select-pve`) — Interactive/CLI tool to select which USB devices to protect. Saves the blacklist to `/etc/usb-blacklist-watcher-pve/blacklist.conf`.
2. **`usb-blacklist-watcher-pve.service`** — Systemd daemon that monitors the QEMU VM configuration directory (`/etc/pve/qemu-server/*.conf`) and the blacklist file via `inotify`. As soon as it detects a change in a VM configuration that adds a blacklisted device, it removes it using `qm set <VMID> --delete usbN` within ~300ms, supporting both hot-unplug (running VMs) and static edits (stopped VMs).

The blacklist uses the `VENDOR:PRODUCT` format (e.g. `2e8a:0005`) for reliable matching regardless of physical USB port changes, and also dynamically translates passthrough configured by physical port (e.g. `host=1-4.2`) in real-time by querying `sysfs`.

---

## Requirements

- Proxmox VE (Debian-based)
- Packages: `bash`, `inotify-tools` (installed automatically as .deb dependencies)
- `dpkg-deb` for building (pre-installed on Debian/Ubuntu/Proxmox)

---

## Building the package

```bash
cd /path/to/usb-blacklist-watcher-pve
chmod +x build-deb.sh
./build-deb.sh
```

This generates `usb-blacklist-watcher-pve_1.1.0_all.deb` in the current directory.

To update the version before building, modify the `src/VERSION` file — `build-deb.sh` will synchronize `src/DEBIAN/control` and name the resulting `.deb` package automatically.

---

## Installation

On a Proxmox VE host node:

```bash
dpkg -i usb-blacklist-watcher-pve_1.1.0_all.deb
# or, with automatic dependency resolution:
apt install ./usb-blacklist-watcher-pve_1.1.0_all.deb
```

The `postinst` script automatically handles:
- Migrating any existing configuration from `/etc/usb-blacklist-watcher/blacklist.conf` to `/etc/usb-blacklist-watcher-pve/blacklist.conf`
- Creating `/etc/usb-blacklist-watcher-pve/blacklist.conf` (if it does not exist)
- Setting restrictive permissions (`600`, `root:root`)
- Enabling and starting the systemd service `usb-blacklist-watcher-pve.service`

---

## Using `usb-blacklist-select`

### Interactive Mode (recommended for initial setup)

```bash
usb-blacklist-select
```

Displays all connected USB devices, indicates which ones are already blacklisted, and allows multiple selection with toggle behavior (selecting a currently blacklisted device removes it).

### CLI Mode (for scripting)

```bash
# Add a device to the blacklist and enforce immediately
usb-blacklist-select --add 2e8a:0005

# Remove a device from the blacklist
usb-blacklist-select --remove 0bda:8156

# List currently blacklisted IDs (one per line, machine-readable)
usb-blacklist-select --list
```

### USB ID Format

The `VENDOR:PRODUCT` IDs match the format shown by `lsusb`, e.g.:
```
Bus 001 Device 003: ID 2e8a:0005 MicroPython Board in FS mode
                        ─────────
                        this is the ID to use
```

---

## Monitoring and Logs

```bash
# Service status
systemctl status usb-blacklist-watcher-pve

# Real-time logs
journalctl -u usb-blacklist-watcher-pve -f

# Current blacklist
cat /etc/usb-blacklist-watcher-pve/blacklist.conf
# or:
usb-blacklist-select --list
```

---

## Testing Enforcement

After adding a device to the blacklist, test assigning it to a VM (by ID or physical port):

```bash
# Assign device (will be removed within ~300ms)
qm set 100 --usb0 host=2e8a:0005

# Or assign via physical port (e.g. 1-4.2)
qm set 100 --usb0 host=1-4.2

# Verify it was removed
grep usb0 /etc/pve/qemu-server/100.conf  # should return empty

# The watcher log will confirm:
journalctl -u usb-blacklist-watcher-pve --no-pager | tail -5
```

---

## Installed File Structure

```
/usr/local/bin/usb-blacklist-select        # interactive CLI tool
/usr/local/bin/usb-blacklist-watcher-pve    # watcher daemon (symlink: usb-blacklist-watcher)
/etc/systemd/system/usb-blacklist-watcher-pve.service (alias: usb-blacklist-watcher.service)
/etc/usb-blacklist-watcher-pve/blacklist.conf  # persistent blacklist
```

---

## Uninstallation

### Simple Removal (preserves blacklist)

```bash
apt remove usb-blacklist-watcher-pve
# or:
dpkg -r usb-blacklist-watcher-pve
```

The directory `/etc/usb-blacklist-watcher-pve/` and its blacklist file are **preserved** for future reinstallation.

### Complete Removal (purge, deletes blacklist)

```bash
apt purge usb-blacklist-watcher-pve
# or:
dpkg -P usb-blacklist-watcher-pve
```

This removes `/etc/usb-blacklist-watcher-pve/` and all its contents.

---

## Technical Notes

- **Why not file permissions on USB devices?** QEMU runs as root on Proxmox VE, so standard Unix file permissions on `/dev/bus/usb` nodes are not an effective boundary.
- **Why not vfio-pci?** That is a PCI-level mechanism and does not apply to USB passthrough via libusb.
- **Why not pre-start hookscripts?** They require manual per-VM assignment, which is error-prone and impractical on nodes where VMs are frequently created or destroyed.
- **Why inotify instead of cron?** The combination of boot-time sweep + inotify on config directories + inotify on the blacklist file provides instant enforcement without polling overhead.
- **Bus-Port support via sysfs:** Dynamically resolves physical port assignments (`host=1-4.2`) by inspecting Vendor and Product IDs in `/sys/bus/usb/devices/` in real time.

---

## Versioning

The package version is defined in the `src/VERSION` file:

```
1.1.0
```

Update this file before running `./build-deb.sh`. The build script will automatically synchronize the version into `src/DEBIAN/control` and produce a package with the new version in the filename.
