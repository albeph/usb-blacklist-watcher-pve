# Developer & AI Agent Guidelines (`usb-blacklist-watcher-pve`)

This document defines the architectural invariants, build workflow, and **Semantic Versioning & Configuration Persistence Policy** that every developer or AI agent working on this repository must follow.

---

## 1. Semantic Versioning & Configuration Persistence Policy

The package version is stored in `src/VERSION` using standard `MAJOR.MINOR.PATCH` format (e.g. `1.2.3`).
When `build-deb.sh` runs, it automatically synchronizes the version from `src/VERSION` into:
- `src/DEBIAN/control` (`Version: ...`)
- `src/DEBIAN/postinst` (`PACKAGE_VERSION="..."`)
- The output `.deb` filename (`usb-blacklist-watcher-pve_<VERSION>_all.deb`)

### Upgrade Behavior (`preinst` + `postinst`)

During package upgrades (`dpkg -i` / `apt install`), `src/DEBIAN/preinst` backs up `/etc/usb-blacklist-watcher-pve/blacklist.conf` and `/etc/usb-blacklist-watcher-pve/advanced.conf` before `dpkg` unpacks the new files, and `src/DEBIAN/postinst` compares the `MAJOR.MINOR` numbers of the previously installed version against the new version:

1. **Patch Updates (`X.Y.z1` $\rightarrow$ `X.Y.z2`, same `MAJOR.MINOR`, e.g. `1.2.2` $\rightarrow$ `1.2.3`)**:
   - **Configuration is preserved automatically**: `blacklist.conf` and `advanced.conf` are restored intact without requiring the user to reconfigure anything.
   - Active Udev rules (`/etc/udev/rules.d/99-usb-blacklist-watcher-pve.rules`) are re-applied and `usb-blacklist-watcher-pve.service` is restarted seamlessly.
   - **When to use**: Bug fixes, UI/UX improvements, performance optimizations, documentation updates, or non-breaking internal changes.

2. **Major or Minor Updates (`X1.Y1.*` $\rightarrow$ `X2.Y2.*`, different `MAJOR.MINOR`, e.g. `1.2.x` $\rightarrow$ `1.3.0` or `1.x.x` $\rightarrow$ `2.0.0`)**:
   - **Configuration is reset**: Previous configuration files are backed up to `blacklist.conf.bak` and `advanced.conf.bak`, clean default configuration files are written, previous Udev rules are cleared, and the post-install banner notifies the user to run `usb-blacklist-select-pve` to reconfigure.
   - **When to use**: ONLY when introducing breaking changes to configuration formats or major new protection mechanisms that require the user to explicitly review and re-select their protected USB devices.

> **IMPORTANT RULE FOR AGENTS / DEVELOPERS**:
> Do **NOT** increment `MAJOR` or `MINOR` in `src/VERSION` unless you intentionally want to force a full configuration reset on upgrade. For all routine fixes and enhancements, increment only the `PATCH` number (e.g. `1.2.2` $\rightarrow$ `1.2.3`).

---

## 2. Component Overview

- **`src/usr/local/bin/usb-blacklist-select-pve`**: Interactive 2-step CLI and non-interactive scripting tool (`--list`, `--add`, `--remove`, `--advanced-list`, `--advanced-add`, `--advanced-remove`).
- **`src/usr/local/bin/usb-blacklist-watcher-pve`**: Systemd daemon using `inotifywait` on `/etc/pve/qemu-server/` and `/etc/usb-blacklist-watcher-pve/`. Note: all `log()` output in the watcher MUST be sent to `stderr` (`>&2`) so it never pollutes `stdout` of functions captured via command substitution `$(...)`.
- **`src/DEBIAN/{preinst,postinst,prerm,postrm}`**: Lifecycle scripts managing configuration persistence, Udev rules (`/etc/udev/rules.d/99-usb-blacklist-watcher-pve.rules`), and the systemd service.

---

## 3. Building & Verification

Always validate bash syntax and build the `.deb` package after making changes:

```bash
bash -n src/usr/local/bin/usb-blacklist-select-pve \
        src/usr/local/bin/usb-blacklist-watcher-pve \
        src/DEBIAN/preinst \
        src/DEBIAN/postinst \
        src/DEBIAN/prerm \
        src/DEBIAN/postrm \
        build-deb.sh
./build-deb.sh
```
