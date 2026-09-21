#!/bin/bash
# build-deb.sh — Script di build del pacchetto usb-blacklist-watcher-pve
#
# Uso:
#   ./build-deb.sh
#
# Output:
#   usb-blacklist-watcher-pve_<VERSION>_all.deb  (nella directory corrente)
#
# Requisiti:
#   dpkg-deb   (pacchetto dpkg, pre-installato su Debian/Ubuntu/Proxmox)
#   fakeroot   (opzionale ma raccomandato; fallback su root diretto)

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURAZIONE
# ─────────────────────────────────────────────────────────────────────────────

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SRC_DIR="${SCRIPT_DIR}/src"
readonly BUILD_DIR="${SCRIPT_DIR}/build"
readonly STAGING_DIR="${BUILD_DIR}/usb-blacklist-watcher-pve"
readonly CONTROL_FILE="${SRC_DIR}/DEBIAN/control"

# ─────────────────────────────────────────────────────────────────────────────
# UTILITY
# ─────────────────────────────────────────────────────────────────────────────

info()    { echo "  [build] $*"; }
error()   { echo "  [build] ERRORE: $*" >&2; }
section() { echo ""; echo "── $* ─────────────────────────────────────────"; }

# ─────────────────────────────────────────────────────────────────────────────
# LETTURA VERSIONE DAL CONTROL FILE
# ─────────────────────────────────────────────────────────────────────────────

get_version() {
    if [ ! -f "${CONTROL_FILE}" ]; then
        error "File control non trovato: ${CONTROL_FILE}"
        exit 1
    fi
    grep -E '^Version:' "${CONTROL_FILE}" | awk '{print $2}' | tr -d '[:space:]'
}

get_package_name() {
    grep -E '^Package:' "${CONTROL_FILE}" | awk '{print $2}' | tr -d '[:space:]'
}

# ─────────────────────────────────────────────────────────────────────────────
# VERIFICA DIPENDENZE DI BUILD
# ─────────────────────────────────────────────────────────────────────────────

check_build_deps() {
    section "Verifica dipendenze di build"
    local ok=1

    if ! command -v dpkg-deb &>/dev/null; then
        error "dpkg-deb non trovato. Installare con: apt install dpkg"
        ok=0
    else
        info "dpkg-deb: OK ($(dpkg-deb --version | head -1))"
    fi

    if [ "${ok}" -eq 0 ]; then
        exit 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# PREPARAZIONE STAGING
# ─────────────────────────────────────────────────────────────────────────────

prepare_staging() {
    section "Preparazione staging in build/"
    info "Sorgenti: ${SRC_DIR}"
    info "Staging:  ${STAGING_DIR}"

    rm -rf "${STAGING_DIR}"
    mkdir -p "${STAGING_DIR}"
    cp -a "${SRC_DIR}/." "${STAGING_DIR}/"
    info "Staging preparato con successo"
}

# ─────────────────────────────────────────────────────────────────────────────
# IMPOSTAZIONE PERMESSI CORRETTI
# ─────────────────────────────────────────────────────────────────────────────

set_permissions() {
    section "Impostazione permessi"

    # Script DEBIAN/ devono essere eseguibili
    chmod 755 "${STAGING_DIR}/DEBIAN/postinst"
    chmod 755 "${STAGING_DIR}/DEBIAN/prerm"
    chmod 755 "${STAGING_DIR}/DEBIAN/postrm"
    info "Script DEBIAN/: 755"

    # Binari installabili
    chmod 755 "${STAGING_DIR}/usr/local/bin/usb-blacklist-watcher-pve"
    chmod 755 "${STAGING_DIR}/usr/local/bin/usb-blacklist-select"
    info "Binari usr/local/bin/: 755"

    # Config di default
    chmod 644 "${STAGING_DIR}/etc/usb-blacklist-watcher-pve/blacklist.conf"
    info "blacklist.conf default: 644 (postinst la imposta a 600 post-install)"

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

    section "Build pacchetto Debian"
    info "Pacchetto:  ${package}"
    info "Versione:   ${version}"
    info "Output:     ${output_file}"
    info "Staging:    ${STAGING_DIR}"

    # Rimuovi eventuale .deb precedente con la stessa versione
    [ -f "${output_file}" ] && rm -f "${output_file}"

    # dpkg-deb --root-owner-group: imposta uid/gid 0 senza richiedere root
    dpkg-deb --root-owner-group --build "${STAGING_DIR}" "${output_file}"

    info "Build completato: ${output_file}"
}

# ─────────────────────────────────────────────────────────────────────────────
# VERIFICA
# ─────────────────────────────────────────────────────────────────────────────

verify_deb() {
    local version package output_file

    version=$(get_version)
    package=$(get_package_name)
    output_file="${SCRIPT_DIR}/${package}_${version}_all.deb"

    section "Verifica pacchetto"

    echo ""
    echo "  ── Metadati (dpkg --info) ───────────────────────────────"
    dpkg --info "${output_file}" | sed 's/^/    /'

    echo ""
    echo "  ── Contenuto (dpkg -c) ──────────────────────────────────"
    dpkg -c "${output_file}" | sed 's/^/    /'

    echo ""
    info "Verifica completata con successo."
    echo ""
    echo "┌────────────────────────────────────────────────────────────┐"
    echo "│  Pacchetto pronto per l'installazione:                      │"
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
    set_permissions
    build_deb
    verify_deb
}

main "$@"
