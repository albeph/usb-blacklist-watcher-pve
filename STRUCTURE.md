# Project Structure: `usb-blacklist-watcher-pve`

```
usb-blacklist-watcher-pve/
│
├── src/                                        # Debian package source files
│   ├── DEBIAN/                                 # Debian package metadata and scripts
│   │   ├── control                             # Name (usb-blacklist-watcher-pve), version, dependencies
│   │   ├── postinst                            # Post-install: create/migrate blacklist.conf, enable service
│   │   ├── prerm                               # Pre-remove: stop and disable service
│   │   └── postrm                              # Post-remove: purge removes /etc/usb-blacklist-watcher-pve/
│   │
│   ├── usr/local/bin/
│   │   ├── usb-blacklist-select                # Interactive CLI tool to manage the blacklist
│   │   ├── usb-blacklist-watcher-pve           # Watcher daemon (inotify monitoring + enforcement)
│   │   ├── usb-blacklist-select-pve -> ...     # Convenience symlink to usb-blacklist-select
│   │   └── usb-blacklist-watcher -> ...        # Backward-compatibility symlink to usb-blacklist-watcher-pve
│   │
│   └── etc/
│       ├── systemd/system/
│       │   └── usb-blacklist-watcher-pve.service # Systemd unit (Restart=always, After=pve-cluster)
│       └── usb-blacklist-watcher-pve/
│           └── blacklist.conf                  # State file with commented header (empty by default)
│
├── build/                                      # Temporary staging directory for dpkg-deb (ignored by Git)
├── .git/                                       # Git repository for version tracking
├── .gitignore                                  # Build exclusion rules (build/, *.deb, temp files)
├── build-deb.sh                                # Build script with auto-versioning from DEBIAN/control
├── README.md                                   # Operational documentation (build, install, usage, purge)
└── STRUCTURE.md                                # This file: detailed project tree
```

---

## Main Files — Summary Description

### `src/DEBIAN/control`
Debian package metadata. Contains package name (`usb-blacklist-watcher-pve`), version, architecture (`all`), and declared dependencies: `bash (>= 4.0)` and `inotify-tools`. Also includes `Provides`, `Replaces`, and `Conflicts` targeting `usb-blacklist-watcher` to ensure clean and seamless upgrades. This file is also the **version source** read automatically by `build-deb.sh` to name the output `.deb` file.

### `src/DEBIAN/postinst`
Executed by `dpkg` after package installation. Handles automatic migration of any existing blacklist from `/etc/usb-blacklist-watcher/blacklist.conf` to `/etc/usb-blacklist-watcher-pve/blacklist.conf`, creates the default file if absent, sets `600 root:root` permissions, stops any previous instances of the old service, and executes `systemctl daemon-reload` and `systemctl enable --now usb-blacklist-watcher-pve.service`.

### `src/DEBIAN/prerm`
Executed by `dpkg` before package removal. Stops (`stop`) and disables (`disable`) the systemd service (`usb-blacklist-watcher-pve.service`, stopping any legacy aliases as well) for clean removal.

### `src/DEBIAN/postrm`
Executed by `dpkg` after package removal. On `purge`, removes the entire `/etc/usb-blacklist-watcher-pve/` directory (and the legacy directory if still present); on simple `remove`, leaves it untouched (the blacklist survives for future reinstallation).

---

### `src/usr/local/bin/usb-blacklist-select`
CLI tool for managing the blacklist (also available via the `usb-blacklist-select-pve` symlink). Two operational modes:

- **Interactive** (no arguments): displays connected USB devices, indicates which are already blacklisted, allows multiple selection with toggle logic, prompts for confirmation, saves, and applies changes.
- **Non-interactive** (for scripting):
  - `--list` → prints blacklisted IDs (one per line)
  - `--add VENDOR:PRODUCT` → adds to blacklist and enforces immediately
  - `--remove VENDOR:PRODUCT` → removes from blacklist and enforces immediately

### `src/usr/local/bin/usb-blacklist-watcher-pve`
Daemon started as a systemd service (also available via legacy symlink `usb-blacklist-watcher`).
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
Persistent state file. Format: one entry per line `VENDOR:PRODUCT  # optional comment`.
Empty lines and lines starting with `#` are ignored. Permissions `600 root:root`.

---

### `build-deb.sh`
Build automation script. Reads version and package name from `src/DEBIAN/control`, stages sources into `build/`, sets correct permissions on all files, invokes `dpkg-deb --root-owner-group --build`, and verifies results with `dpkg --info` and `dpkg -c`.
