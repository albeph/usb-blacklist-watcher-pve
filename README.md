# usb-blacklist-watcher-pve

Pacchetto Debian per nodi **Proxmox VE** che impedisce che specifici dispositivi USB dell'host vengano assegnati (passthrough) a macchine virtuali QEMU — né manualmente dalla GUI, né via CLI, né a VM già accese.

---

## Come funziona

Il pacchetto installa due componenti:

1. **`usb-blacklist-select`** (alias: `usb-blacklist-select-pve`) — Tool interattivo/CLI per scegliere quali device USB proteggere. Salva la blacklist in `/etc/usb-blacklist-watcher-pve/blacklist.conf`.
2. **`usb-blacklist-watcher-pve.service`** — Daemon systemd che monitora via `inotify` la directory dei conf VM QEMU (`/etc/pve/qemu-server/*.conf`) e il file di blacklist. Appena rileva una modifica a un conf che aggiunge un device in blacklist, lo rimuove con `qm set <VMID> --delete usbN` entro ~300ms, supportando sia hot-unplug (VM accese) sia edit statici (VM spente).

La blacklist usa il formato `VENDOR:PRODUCT` (es. `2e8a:0005`) per un matching affidabile indipendentemente dalla porta USB fisica, e traduce dinamicamente in tempo reale anche i passthrough configurati via porta fisica (es. `host=1-4.2`) leggendo le informazioni direttamente da `sysfs`.

---

## Requisiti

- Proxmox VE (Debian-based)
- Pacchetti: `bash`, `inotify-tools` (installati automaticamente come dipendenze del .deb)
- `dpkg-deb` per il build (pre-installato su Debian)

---

## Build del pacchetto

```bash
cd /path/to/usb-blacklist-watcher
chmod +x build-deb.sh
./build-deb.sh
```

Questo produce `usb-blacklist-watcher-pve_1.1.0_all.deb` nella directory corrente.

Per aggiornare la versione prima del build, modifica la riga `Version:` in `build/usb-blacklist-watcher-pve/DEBIAN/control` — il nome del file .deb verrà aggiornato automaticamente.

---

## Installazione

Su un nodo Proxmox VE:

```bash
dpkg -i usb-blacklist-watcher-pve_1.1.0_all.deb
# oppure, con gestione automatica delle dipendenze:
apt install ./usb-blacklist-watcher-pve_1.1.0_all.deb
```

Il `postinst` si occupa automaticamente di:
- Migrare eventuale configurazione precedente da `/etc/usb-blacklist-watcher/blacklist.conf` a `/etc/usb-blacklist-watcher-pve/blacklist.conf`
- Creare `/etc/usb-blacklist-watcher-pve/blacklist.conf` (se non esiste)
- Impostare i permessi corretti (`600`, `root:root`)
- Abilitare e avviare il servizio systemd `usb-blacklist-watcher-pve.service`

---

## Utilizzo di `usb-blacklist-select`

### Modalità interattiva (consigliata per la configurazione iniziale)

```bash
usb-blacklist-select
```

Mostra tutti i device USB collegati, indica quali sono già in blacklist, e permette la selezione multipla con comportamento toggle (riselezionare un device già in blacklist lo rimuove).

### Modalità CLI (per scripting)

```bash
# Aggiunge un device alla blacklist e applica enforcement immediato
usb-blacklist-select --add 2e8a:0005

# Rimuove un device dalla blacklist
usb-blacklist-select --remove 0bda:8156

# Lista gli ID attualmente in blacklist (uno per riga, formato machine-readable)
usb-blacklist-select --list
```

### Formato degli ID USB

Gli ID `VENDOR:PRODUCT` sono quelli mostrati da `lsusb`, es.:
```
Bus 001 Device 003: ID 2e8a:0005 MicroPython Board in FS mode
                        ─────────
                        questo è l'ID da usare
```

---

## Monitoraggio e log

```bash
# Stato del servizio
systemctl status usb-blacklist-watcher-pve

# Log in tempo reale
journalctl -u usb-blacklist-watcher-pve -f

# Blacklist corrente
cat /etc/usb-blacklist-watcher-pve/blacklist.conf
# oppure:
usb-blacklist-select --list
```

---

## Test dell'enforcement

Dopo aver aggiunto un device alla blacklist, prova ad assegnarlo a una VM (sia per ID che per porta fisica):

```bash
# Assegna il device (verrà rimosso entro ~300ms)
qm set 100 --usb0 host=2e8a:0005

# Oppure assegna la porta fisica a cui è collegato (es. 1-4.2)
qm set 100 --usb0 host=1-4.2

# Verifica che sia stato rimosso
grep usb0 /etc/pve/qemu-server/100.conf  # non deve apparire

# Il log del watcher mostrerà:
journalctl -u usb-blacklist-watcher-pve --no-pager | tail -5
```

---

## Struttura file installati

```
/usr/local/bin/usb-blacklist-select        # tool interattivo
/usr/local/bin/usb-blacklist-watcher-pve    # daemon watcher (symlink: usb-blacklist-watcher)
/etc/systemd/system/usb-blacklist-watcher-pve.service (alias: usb-blacklist-watcher.service)
/etc/usb-blacklist-watcher-pve/blacklist.conf  # blacklist persistente
```

---

## Disinstallazione

### Rimozione semplice (conserva la blacklist)

```bash
apt remove usb-blacklist-watcher-pve
# oppure:
dpkg -r usb-blacklist-watcher-pve
```

La directory `/etc/usb-blacklist-watcher-pve/` con la blacklist viene **conservata** per un eventuale reinstall successivo.

### Rimozione completa (purge, cancella anche la blacklist)

```bash
apt purge usb-blacklist-watcher-pve
# oppure:
dpkg -P usb-blacklist-watcher-pve
```

Questo rimuove anche `/etc/usb-blacklist-watcher-pve/` e tutti i suoi contenuti.

---

## Note tecniche

- **Perché non permessi file USB?** QEMU su Proxmox gira come root, quindi i permessi Unix sui device node USB non sono una barriera efficace.
- **Perché non vfio-pci?** È un meccanismo PCI, non applicabile al passthrough USB via libusb.
- **Perché non hookscript pre-start?** Richiederebbe assegnazione manuale per ogni VM, poco pratico su nodi con VM create/distrutte di frequente.
- **Perché inotify e non cron?** La combinazione "check al boot + inotify sui conf + inotify sulla blacklist" offre reattività immediata senza polling.
- **Supporto Bus-Port tramite sysfs:** Risolve dinamicamente le assegnazioni tramite porta fisica (`host=1-4.2`) verificando Vendor e Product in `/sys/bus/usb/devices/` in tempo reale.

---

## Versioning

La versione del pacchetto è definita in `build/usb-blacklist-watcher-pve/DEBIAN/control`:

```
Version: 1.1.0
```

Modificare questo valore prima di eseguire `./build-deb.sh` per produrre un pacchetto con il nuovo numero di versione nel nome file.
