# usb-blacklist-watcher-pve

Debian package for **Proxmox VE** nodes that prevents specific host USB devices from being passed through to QEMU virtual machines — neither manually via GUI or CLI, nor to already running VMs.

---

## How it works

The package provides two layers of protection managed through two components:

1. **`usb-blacklist-select-pve`** — Interactive/CLI tool to select which USB devices to protect via:
   - **Standard Blacklist** (`/etc/usb-blacklist-watcher-pve/blacklist.conf`): watched by the daemon to strip disallowed USB devices from VM configurations.
   - **Advanced Protection** (`/etc/usb-blacklist-watcher-pve/advanced.conf` + `/etc/udev/rules.d/99-usb-blacklist-watcher-pve.rules`): optional Udev rule for critical host devices (such as USB/SD boot drives or thermal/fan microcontrollers like Raspberry Pi Pico) that deletes the raw USB node (`/dev/bus/usb/XXX/YYY`) upon detection while leaving kernel-managed device nodes (`/dev/sdX`, `/dev/ttyACM0`, etc.) completely intact. Without the raw USB node, neither `root` nor QEMU/KVM can issue `USBDEVFS_DISCONNECT` to detach the host kernel driver, preventing even a momentary disconnect.
2. **`usb-blacklist-watcher-pve.service`** — Systemd daemon that monitors the QEMU VM configuration directory (`/etc/pve/qemu-server/*.conf`) and the blacklist file via `inotify`. As soon as it detects a change in a VM configuration that adds a blacklisted device, it removes it using `qm set <VMID> --delete usbN` within ~300ms, supporting both hot-unplug (running VMs) and static edits (stopped VMs).

Both protection levels use the `VENDOR:PRODUCT` format (e.g. `2e8a:0005`) for reliable matching regardless of physical USB port changes, and the watcher also dynamically translates passthrough configured by physical port (e.g. `host=1-4.2`) in real-time by querying `sysfs`.

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

This generates `usb-blacklist-watcher-pve_1.2.3_all.deb` in the current directory.

To update the version before building, modify the `src/VERSION` file — `build-deb.sh` will synchronize `src/DEBIAN/control`, `src/DEBIAN/postinst`, and name the resulting `.deb` package automatically.

---

## Installation & Upgrades

On a Proxmox VE host node:

```bash
dpkg -i usb-blacklist-watcher-pve_1.2.3_all.deb
# or, with automatic dependency resolution:
apt install ./usb-blacklist-watcher-pve_1.2.3_all.deb
```

The `preinst` and `postinst` scripts automatically handle:
- **Patch upgrades (e.g. `1.2.1` $\rightarrow$ `1.2.2` $\rightarrow$ `1.2.3`)**: Your existing `blacklist.conf`, `advanced.conf`, and Udev rules are **automatically preserved** without requiring reconfiguration.
- **Major / Minor upgrades (e.g. `1.2.x` $\rightarrow$ `1.3.x` or `1.x.x` $\rightarrow$ `2.x.x`)**: Previous configuration files are backed up to `.bak` and reset to clean defaults so you can reconfigure for the new version with `usb-blacklist-select-pve`.
- Setting restrictive permissions (`600`, `root:root`)
- Enabling and restarting the systemd service `usb-blacklist-watcher-pve.service`

---

## Using `usb-blacklist-select-pve`

### Interactive Mode (2-step sequential flow)

```bash
usb-blacklist-select-pve
```

1. **Step 1/2 — Standard Blacklist**: Displays all connected USB devices, indicates which ones are already blacklisted (and which have Advanced Protection active), and allows multiple toggle selection. Pressing `ENTER` without input keeps the current blacklist unchanged and proceeds directly to Step 2.
2. **Step 2/2 — Advanced Protection (Udev Raw Node Block)**: Displays only the currently blacklisted USB devices and lets you toggle Udev-level raw node removal (`/dev/bus/usb/XXX/YYY`) for critical devices. Changes are applied immediately without rebooting via `udevadm control --reload-rules && udevadm trigger --subsystem-match=usb`.

### CLI Mode (for scripting)

```bash
# Add a device to the standard blacklist and enforce immediately
usb-blacklist-select-pve --add 2e8a:0005

# Remove a device from the blacklist (and from Advanced Protection if active)
usb-blacklist-select-pve --remove 0bda:8156

# List currently blacklisted IDs (one per line, machine-readable)
usb-blacklist-select-pve --list

# Enable Advanced Protection (Udev raw node removal) for a device
# (automatically adds the device to the standard blacklist if not already present)
usb-blacklist-select-pve --advanced-add 0bda:0177

# Disable Advanced Protection while keeping the device in the standard blacklist
# (immediately restores the /dev/bus/usb/XXX/YYY node via udevadm)
usb-blacklist-select-pve --advanced-remove 2e8a:0005

# List IDs with Advanced Protection enabled (one per line)
usb-blacklist-select-pve --advanced-list
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

# Current blacklist & Advanced Protection
usb-blacklist-select-pve --list
usb-blacklist-select-pve --advanced-list

# Active Udev rules for Advanced Protection
cat /etc/udev/rules.d/99-usb-blacklist-watcher-pve.rules
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

## Uninstallation

### Simple Removal (preserves configuration, restores raw USB nodes)

```bash
apt remove usb-blacklist-watcher-pve
# or:
dpkg -r usb-blacklist-watcher-pve
```

The directory `/etc/usb-blacklist-watcher-pve/` (`blacklist.conf` and `advanced.conf`) is **preserved** for future reinstallation, while `/etc/udev/rules.d/99-usb-blacklist-watcher-pve.rules` is removed and `udevadm` is triggered so raw USB nodes are restored.

### Complete Removal (purge, deletes all configuration)

```bash
apt purge usb-blacklist-watcher-pve
# or:
dpkg -P usb-blacklist-watcher-pve
```

This removes `/etc/usb-blacklist-watcher-pve/`, all its contents, and any generated Udev rules.

---

## Technical Notes

- **Why Advanced Protection (Udev raw node removal)?** When QEMU (`kvm`, running as `root`) attempts USB passthrough on a running VM, it opens `/dev/bus/usb/XXX/YYY` and sends `USBDEVFS_DISCONNECT` to detach the host kernel driver (`usb-storage`, `cdc_acm`, etc.). Even if the watcher removes the configuration entry 300ms later, a momentary disconnect on a USB/SD boot drive causes Linux to remount `/` as Read-Only. Removing `/dev/bus/usb/XXX/YYY` via a Udev rule (`RUN+="/bin/rm -f $env{DEVNAME}"`) prevents user-space programs from detaching the kernel driver while keeping `/dev/sdX` and `/dev/ttyACM*` 100% functional.
- **Why not file permissions on USB devices?** QEMU runs as root on Proxmox VE, so standard Unix file permissions on `/dev/bus/usb` nodes are not an effective boundary.
- **Why not vfio-pci?** That is a PCI-level mechanism and does not apply to USB passthrough via libusb.
- **Why not pre-start hookscripts?** They require manual per-VM assignment, which is error-prone and impractical on nodes where VMs are frequently created or destroyed.
- **Why inotify instead of cron?** The combination of boot-time sweep + inotify on config directories + inotify on the blacklist file provides instant enforcement without polling overhead.
- **Bus-Port support via sysfs:** Dynamically resolves physical port assignments (`host=1-4.2`) by inspecting Vendor and Product IDs in `/sys/bus/usb/devices/` in real time.

---

## Versioning

The package version is defined in the `src/VERSION` file.

Update this file before running `./build-deb.sh`. The build script will automatically synchronize the version into `src/DEBIAN/control` and produce a package with the new version in the filename.
