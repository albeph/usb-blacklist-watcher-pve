#!/bin/bash
# build-deb.sh — Build script for usb-blacklist-watcher-pve Debian package
#
# Usage:
#   ./build-deb.sh
#
# Output:
#   usb-blacklist-watcher-pve_<VERSION>_all.deb  (in current directory)
#
# Requirements:
#   dpkg-deb   (dpkg package, pre-installed on Debian/Ubuntu/Proxmox)
#   fakeroot   (optional but recommended; fallback to direct root)

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly VERSION_FILE="${SCRIPT_DIR}/VERSION"
readonly SRC_DIR="${SCRIPT_DIR}/src"
readonly BUILD_DIR="${SCRIPT_DIR}/build"
readonly STAGING_DIR="${BUILD_DIR}/usb-blacklist-watcher-pve"
readonly CONTROL_FILE="${SRC_DIR}/DEBIAN/control"

# ─────────────────────────────────────────────────────────────────────────────
# UTILITIES
# ─────────────────────────────────────────────────────────────────────────────

info()    { echo "  [build] $*"; }
error()   { echo "  [build] ERROR: $*" >&2; }
section() { echo ""; echo "── $* ─────────────────────────────────────────"; }

# ─────────────────────────────────────────────────────────────────────────────
# READ VERSION
# ─────────────────────────────────────────────────────────────────────────────

get_version() {
    if [ -f "${VERSION_FILE}" ]; then
        tr -d '[:space:]' < "${VERSION_FILE}"
    elif [ -f "${CONTROL_FILE}" ]; then
        grep -E '^Version:' "${CONTROL_FILE}" | awk '{print $2}' | tr -d '[:space:]'
    else
        error "Neither VERSION file (${VERSION_FILE}) nor control file (${CONTROL_FILE}) found."
        exit 1
    fi
}

get_package_name() {
    grep -E '^Package:' "${CONTROL_FILE}" | awk '{print $2}' | tr -d '[:space:]'
}

# ─────────────────────────────────────────────────────────────────────────────
# CHECK BUILD DEPENDENCIES
# ─────────────────────────────────────────────────────────────────────────────

check_build_deps() {
    section "Check build dependencies"
    local ok=1

    if ! command -v dpkg-deb &>/dev/null; then
        error "dpkg-deb not found. Install with: apt install dpkg"
        ok=0
    else
        info "dpkg-deb: OK ($(dpkg-deb --version | head -1))"
    fi

    if [ "${ok}" -eq 0 ]; then
        exit 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# STAGING PREPARATION
# ─────────────────────────────────────────────────────────────────────────────

prepare_staging() {
    section "Prepare staging in build/"
    info "Sources: ${SRC_DIR}"
    info "Staging: ${STAGING_DIR}"

    rm -rf "${STAGING_DIR}"
    mkdir -p "${STAGING_DIR}"
    cp -a "${SRC_DIR}/." "${STAGING_DIR}/"
    info "Staging prepared successfully"
}

# ─────────────────────────────────────────────────────────────────────────────
# SYNCHRONIZE VERSION
# ─────────────────────────────────────────────────────────────────────────────

sync_version() {
    section "Synchronize version"
    local version
    version=$(get_version)

    if [ -z "${version}" ]; then
        error "Version string is empty."
        exit 1
    fi

    # Synchronize control files with VERSION
    if [ -f "${CONTROL_FILE}" ]; then
        sed -i -E "s/^Version:.*/Version: ${version}/" "${CONTROL_FILE}"
    fi
    if [ -f "${STAGING_DIR}/DEBIAN/control" ]; then
        sed -i -E "s/^Version:.*/Version: ${version}/" "${STAGING_DIR}/DEBIAN/control"
    fi
    info "Version synchronized: ${version}"
}

# ─────────────────────────────────────────────────────────────────────────────
# SET CORRECT PERMISSIONS
# ─────────────────────────────────────────────────────────────────────────────

set_permissions() {
    section "Set permissions"

    # DEBIAN/ scripts must be executable
    chmod 755 "${STAGING_DIR}/DEBIAN/postinst"
    chmod 755 "${STAGING_DIR}/DEBIAN/prerm"
    chmod 755 "${STAGING_DIR}/DEBIAN/postrm"
    info "DEBIAN/ scripts: 755"

    # Installable binaries
    chmod 755 "${STAGING_DIR}/usr/local/bin/usb-blacklist-watcher-pve"
    chmod 755 "${STAGING_DIR}/usr/local/bin/usb-blacklist-select"
    info "usr/local/bin/ binaries: 755"

    # Default config
    chmod 644 "${STAGING_DIR}/etc/usb-blacklist-watcher-pve/blacklist.conf"
    info "default blacklist.conf: 644 (postinst sets 600 post-install)"

    # Systemd unit
    chmod 644 "${STAGING_DIR}/etc/systemd/system/usb-blacklist-watcher-pve.service"
    info "Service unit: 644"
}

# ─────────────────────────────────────────────────────────────────────────────
# BUILD
# ─────────────────────────────────────────────────────────────────────────────

build_deb() {
    local version package output_file

    version=$(get_version)
    package=$(get_package_name)
    output_file="${SCRIPT_DIR}/${package}_${version}_all.deb"

    section "Build Debian package"
    info "Package:  ${package}"
    info "Version:  ${version}"
    info "Output:   ${output_file}"
    info "Staging:  ${STAGING_DIR}"

    # Remove any previous .deb with the same version
    [ -f "${output_file}" ] && rm -f "${output_file}"

    # dpkg-deb --root-owner-group: set uid/gid 0 without requiring root
    dpkg-deb --root-owner-group --build "${STAGING_DIR}" "${output_file}"

    info "Build completed: ${output_file}"
}

# ─────────────────────────────────────────────────────────────────────────────
# VERIFICATION
# ─────────────────────────────────────────────────────────────────────────────

verify_deb() {
    local version package output_file

    version=$(get_version)
    package=$(get_package_name)
    output_file="${SCRIPT_DIR}/${package}_${version}_all.deb"

    section "Verify package"

    echo ""
    echo "  ── Metadata (dpkg --info) ───────────────────────────────"
    dpkg --info "${output_file}" | sed 's/^/    /'

    echo ""
    echo "  ── Contents (dpkg -c) ───────────────────────────────────"
    dpkg -c "${output_file}" | sed 's/^/    /'

    echo ""
    info "Verification completed successfully."
    echo ""
    echo "┌────────────────────────────────────────────────────────────┐"
    echo "│  Package ready for installation:                           │"
    echo "│                                                              │"
    echo "│    dpkg -i ${package}_${version}_all.deb"
    echo "│                                                              │"
    echo "└────────────────────────────────────────────────────────────┘"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║      usb-blacklist-watcher-pve — Build Script              ║"
    echo "╚════════════════════════════════════════════════════════════╝"

    check_build_deps
    prepare_staging
    sync_version
    set_permissions
    build_deb
    verify_deb
}

main "$@"
