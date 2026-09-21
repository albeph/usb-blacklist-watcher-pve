# Struttura del Progetto: `usb-blacklist-watcher-pve`

```
usb-blacklist-watcher/
│
├── src/                                        # File sorgente del pacchetto Debian
│   ├── DEBIAN/                             # Metadati e script del pacchetto Debian
│   │   ├── control                         # Nome (usb-blacklist-watcher-pve), versione, dipendenze
│   │   ├── postinst                        # Post-install: crea/migra blacklist.conf, abilita servizio
│   │   ├── prerm                           # Pre-remove: ferma e disabilita il servizio
│   │   └── postrm                          # Post-remove: purge rimuove /etc/usb-blacklist-watcher-pve/
│   │
│   ├── usr/local/bin/
│   │   ├── usb-blacklist-select            # Tool CLI interattivo per gestire la blacklist
│   │   ├── usb-blacklist-watcher-pve        # Daemon watcher (monitoraggio inotify + enforcement)
│   │   ├── usb-blacklist-select-pve -> ... # Symlink di convenienza a usb-blacklist-select
│   │   └── usb-blacklist-watcher -> ...    # Symlink di retrocompatibilità a usb-blacklist-watcher-pve
│   │
│   └── etc/
│       ├── systemd/system/
│       │   └── usb-blacklist-watcher-pve.service # Unit systemd (Restart=always, After=pve-cluster)
│       └── usb-blacklist-watcher-pve/
│           └── blacklist.conf              # File di stato con header commentato (default vuoto)
│
├── build/                                      # Cartella temporanea di staging per dpkg-deb (ignorata da Git)
├── usb-blacklist-watcher_1.0.0_all.deb        # Versione iniziale (legacy name)
├── usb-blacklist-watcher_1.0.1_all.deb        # Fix: inotify su symlink pmxcfs
├── usb-blacklist-watcher_1.0.2_all.deb        # Fix: bypass via passthrough bus-port (sysfs)
├── usb-blacklist-watcher_1.0.3_all.deb        # Ottimizzazioni: debounce async, caching blacklist
├── usb-blacklist-watcher-pve_1.1.0_all.deb    # Rename progetto a usb-blacklist-watcher-pve
│
├── .git/                                       # Repository Git per tracciamento versioni
├── .gitignore                                  # Regole di esclusione file di build (build/, *.deb, temp)
├── build-deb.sh                                # Script di build con auto-versioning da DEBIAN/control
├── README.md                                   # Documentazione operativa (build, install, uso, purge)
├── RELAZIONE_PROGETTO.md                       # Relazione tecnica: storia e motivazioni di ogni versione
└── STRUTTURA.md                                # Questo file: albero dettagliato del progetto
```

---

## File principali — Descrizione sintetica

### `src/DEBIAN/control`
Metadati del pacchetto Debian. Contiene nome pacchetto (`usb-blacklist-watcher-pve`), versione, architettura (`all`) e le dipendenze
dichiarate: `bash (>= 4.0)` e `inotify-tools`. Include inoltre `Provides`, `Replaces` e `Conflicts` verso `usb-blacklist-watcher`
per garantire un upgrade pulito e trasparente. Questo file è anche la **sorgente della versione**
letta automaticamente da `build-deb.sh` per nominare il file `.deb` in output.

### `src/DEBIAN/postinst`
Eseguito da `dpkg` dopo l'installazione. Gestisce la migrazione automatica di eventuali blacklist esistenti da
`/etc/usb-blacklist-watcher/blacklist.conf` a `/etc/usb-blacklist-watcher-pve/blacklist.conf`, crea il file se assente,
imposta i permessi `600 root:root`, ferma eventuali istanze precedenti del vecchio servizio,
ed esegue `systemctl daemon-reload` e `systemctl enable --now usb-blacklist-watcher-pve.service`.

### `src/DEBIAN/prerm`
Eseguito da `dpkg` prima della rimozione. Ferma (`stop`) e disabilita (`disable`) il servizio
systemd (`usb-blacklist-watcher-pve.service`, arrestando anche l'eventuale alias legacy) per una rimozione pulita.

### `src/DEBIAN/postrm`
Eseguito da `dpkg` dopo la rimozione. In caso di `purge` rimuove l'intera directory
`/etc/usb-blacklist-watcher-pve/` (e la vecchia se ancora presente); in caso di `remove` semplice la lascia intatta (la blacklist
sopravvive per una eventuale reinstallazione).

---

### `usr/local/bin/usb-blacklist-select`
Tool CLI per la gestione della blacklist (disponibile anche tramite symlink `usb-blacklist-select-pve`). Due modalità operative:

- **Interattiva** (nessun argomento): mostra i dispositivi USB collegati, indica quelli già in
  blacklist, permette selezione multipla con logica toggle, chiede conferma, salva e applica.
- **Non interattiva** (per scripting):
  - `--list` → stampa gli ID in blacklist (uno per riga)
  - `--add VENDOR:PRODUCT` → aggiunge e applica enforcement immediato
  - `--remove VENDOR:PRODUCT` → rimuove e applica enforcement immediato

### `usr/local/bin/usb-blacklist-watcher-pve`
Daemon avviato come servizio systemd (disponibile anche tramite symlink legacy `usb-blacklist-watcher`).
All'avvio esegue un enforcement su tutti i `.conf` esistenti, poi entra in un loop `inotifywait` che monitora due percorsi:
- `/etc/pve/qemu-server/` — per ogni modifica a un `.conf` VM, applica enforcement su quella VM
- `/etc/usb-blacklist-watcher-pve/` — se la blacklist cambia, applica enforcement su tutte le VM

Supporta entrambi i formati di passthrough Proxmox:
- `host=VENDOR:PRODUCT` → match diretto sulla blacklist
- `host=BUS-PORT` (es. `1-4.2`) → traduzione in tempo reale via `/sys/bus/usb/devices/`

### `etc/systemd/system/usb-blacklist-watcher-pve.service`
Unit systemd con `Restart=always`, `After=pve-cluster.service`, `Wants=pve-cluster.service`.
Include un alias verso `usb-blacklist-watcher.service` per garantire retrocompatibilità.

### `etc/usb-blacklist-watcher-pve/blacklist.conf`
File di stato persistente. Formato: una entry per riga `VENDOR:PRODUCT  # commento opzionale`.
Righe vuote e righe che iniziano con `#` vengono ignorate. Permessi `600 root:root`.

---

### `build-deb.sh`
Script di automazione del build. Legge la versione e il nome del pacchetto da `DEBIAN/control`,
imposta i permessi corretti su tutti i file, chiama `dpkg-deb --root-owner-group --build` e verifica il risultato
con `dpkg --info` e `dpkg -c`.
