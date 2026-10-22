# Project Structure: `usb-blacklist-watcher-pve`

```
usb-blacklist-watcher-pve/
│
├── src/                                        # Debian package source files
│   ├── DEBIAN/                                 # Debian package metadata and scripts
│   │   ├── control                             # Name (usb-blacklist-watcher-pve), version, dependencies
│   │   ├── preinst                             # Pre-install: backs up existing configs before dpkg unpack
│   │   ├── postinst                            # Post-install: preserves configs on patch updates, resets on Major/Minor
│   │   ├── prerm                               # Pre-remove: stop/disable service, clean up udev rules on remove
│   │   └── postrm                              # Post-remove: purge removes /etc/usb-blacklist-watcher-pve/ & udev rules
│   │
│   ├── usr/local/bin/
│   │   ├── usb-blacklist-select-pve            # Interactive/CLI tool to manage Blacklist & Advanced Protection
│   │   └── usb-blacklist-watcher-pve           # Watcher daemon (inotify monitoring + enforcement)
│   │
│   ├── etc/
│   │   ├── systemd/system/
│   │   │   └── usb-blacklist-watcher-pve.service # Systemd unit (Restart=always, After=pve-cluster)
│   │   └── usb-blacklist-watcher-pve/
│   │       ├── blacklist.conf                  # Standard blacklist state file (empty by default)
│   │       └── advanced.conf                   # Advanced Protection (Udev raw node block) state file
│   │
│   └── VERSION                                 # Package version definition file (e.g. 1.2.3)
│
├── build/                                      # Temporary staging directory for dpkg-deb (ignored by Git)
├── .git/                                       # Git repository for version tracking
├── .gitignore                                  # Build exclusion rules (build/, *.deb, temp files)
├── build-deb.sh                                # Build script with auto-versioning from src/VERSION
├── AGENTS.md                                   # Developer & AI Agent guidelines (versioning & upgrade policy)
├── README.md                                   # Operational documentation (build, install, usage, purge)
└── STRUCTURE.md                                # This file: detailed project tree
```

---

## Main Files — Summary Description

### `src/DEBIAN/control`
Debian package metadata. Contains package name (`usb-blacklist-watcher-pve`), version, architecture (`all`), and declared dependencies: `bash (>= 4.0)` and `inotify-tools`. Also includes `Provides`, `Replaces`, and `Conflicts` targeting `usb-blacklist-watcher` to ensure clean and seamless upgrades. The `Version:` field is automatically synchronized from `src/VERSION` by `build-deb.sh`.

### `src/DEBIAN/preinst`
Executed by `dpkg` before unpacking a new package version. Backs up existing `/etc/usb-blacklist-watcher-pve/blacklist.conf` and `/etc/usb-blacklist-watcher-pve/advanced.conf` (along with the previous version string) so `dpkg` unpacking the default templates does not overwrite user configuration during patch upgrades.

### `src/DEBIAN/postinst`
Executed by `dpkg` after package unpack. Implements version-aware configuration management:
- **Patch upgrades (`X.Y.z1` $\rightarrow$ `X.Y.z2`, same `MAJOR.MINOR`, e.g. `1.2.2` $\rightarrow$ `1.2.3`)**: automatically restores `blacklist.conf` and `advanced.conf` from the `preinst` backup, re-applies active Udev rules, and restarts the watcher service without requiring user reconfiguration.
- **Major/Minor upgrades (`X1.Y1.*` $\rightarrow$ `X2.Y2.*`, different `MAJOR.MINOR`, e.g. `1.2.x` $\rightarrow$ `1.3.x` or `1.x.x` $\rightarrow$ `2.x.x`)**: archives old configs to `.bak`, initializes clean default configs, removes old Udev rules, and notifies the user to reconfigure with `usb-blacklist-select-pve`.

### `src/DEBIAN/prerm`
Executed by `dpkg` before package removal. Stops (`stop`) and disables (`disable`) the systemd service (`usb-blacklist-watcher-pve.service`), and on `remove`/`deconfigure` removes `/etc/udev/rules.d/99-usb-blacklist-watcher-pve.rules` and triggers `udevadm` to restore raw USB device nodes.

### `src/DEBIAN/postrm`
Executed by `dpkg` after package removal. On `purge`, removes `/etc/udev/rules.d/99-usb-blacklist-watcher-pve.rules` and the entire `/etc/usb-blacklist-watcher-pve/` directory (and the legacy directory if still present); on simple `remove`, leaves `/etc/usb-blacklist-watcher-pve/` untouched so configuration survives for future reinstallation.

---

### `src/usr/local/bin/usb-blacklist-select-pve`
CLI tool for managing the blacklist and Advanced Protection. Two operational modes:

- **Interactive** (no arguments): 2-step sequential flow with visual step banners and highlighted input boxes:
  1. **Step 1/2 (Blacklist Standard)**: displays connected USB devices, indicates which are already blacklisted or have Advanced Protection enabled, allows multiple toggle selection, prompts for confirmation, saves, and applies VM enforcement.
  2. **Step 2/2 (Advanced Protection)**: lists the currently blacklisted USB devices and allows toggling Udev-based raw node protection (`RUN+="/bin/rm -f $env{DEVNAME}"` in `/etc/udev/rules.d/99-usb-blacklist-watcher-pve.rules`), immediately reloading and triggering `udevadm`.
- **Non-interactive** (for scripting):
  - `--list` → prints blacklisted IDs (one per line)
  - `--add VENDOR:PRODUCT` → adds to blacklist and enforces immediately
  - `--remove VENDOR:PRODUCT` → removes from blacklist (and from Advanced Protection if active) and enforces immediately
  - `--advanced-list` → prints IDs with Advanced Protection enabled (one per line)
  - `--advanced-add VENDOR:PRODUCT` → enables Advanced Protection (adding to standard blacklist as well if absent) and reloads Udev rules immediately
  - `--advanced-remove VENDOR:PRODUCT` → disables Advanced Protection while keeping the device in standard blacklist, restoring the `/dev/bus/usb/XXX/YYY` raw node via `udevadm`

### `src/usr/local/bin/usb-blacklist-watcher-pve`
Daemon started as a systemd service.
On startup, runs an initial enforcement pass on all existing `.conf` files, then enters an `inotifywait` loop monitoring two paths:
- `/etc/pve/qemu-server/` — on every VM `.conf` modification, enforces rules on that VM
- `/etc/usb-blacklist-watcher-pve/` — if the blacklist changes, enforces rules across all VMs

Supports both Proxmox passthrough formats:
- `host=VENDOR:PRODUCT` → direct match against the blacklist
- `host=BUS-PORT` (e.g. `1-4.2`) → real-time dynamic translation via `/sys/bus/usb/devices/`

### `src/etc/systemd/system/usb-blacklist-watcher-pve.service`
Systemd unit with `Restart=always`, `After=pve-cluster.service`, `Wants=pve-cluster.service`.
Includes an alias to `usb-blacklist-watcher.service` for backward compatibility.

### `src/etc/usb-blacklist-watcher-pve/blacklist.conf`
Persistent state file for the standard blacklist. Format: one entry per line `VENDOR:PRODUCT  # optional comment`.
Empty lines and lines starting with `#` are ignored. Permissions `600 root:root`.

### `src/etc/usb-blacklist-watcher-pve/advanced.conf`
Persistent state file for Advanced Protection (subset of blacklisted devices whose raw USB nodes `/dev/bus/usb/XXX/YYY` are removed via `/etc/udev/rules.d/99-usb-blacklist-watcher-pve.rules`). Format: one entry per line `VENDOR:PRODUCT  # optional comment`. Permissions `600 root:root`.

---

### `build-deb.sh`
Build automation script. Reads the version from `src/VERSION` and package name from `src/DEBIAN/control`, synchronizes the version into `control` and `postinst`, stages sources into `build/`, sets correct permissions on all files, invokes `dpkg-deb --root-owner-group --build`, and verifies results with `dpkg --info` and `dpkg -c`.

### `src/VERSION`
Defines the package version string (e.g. `1.2.3`). Read by `build-deb.sh` as the single source of truth for package versioning. Follow the rules in `AGENTS.md` when incrementing `MAJOR.MINOR.PATCH` (patch updates preserve user configuration; major/minor updates reset configuration).
