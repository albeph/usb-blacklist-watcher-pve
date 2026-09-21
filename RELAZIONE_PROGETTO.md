# Relazione di Progetto: `usb-blacklist-watcher-pve`

## 1. Introduzione e Obiettivo del Progetto

Il pacchetto Debian `usb-blacklist-watcher-pve` è una soluzione di sicurezza progettata per nodi **Proxmox VE** (Debian-based). L'obiettivo primario è impedire in modo automatizzato, deterministico e in tempo reale che specifici dispositivi USB dell'host possano mai essere assegnati in passthrough ad alcuna macchina virtuale QEMU/KVM — indipendentemente dal fatto che l'assegnazione avvenga via interfaccia web Proxmox GUI, via CLI (`qm set`), o che la macchina virtuale si trovi in stato acceso (hot-unplug) o spento (edit statico).

### Architettura Generale

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            INTERFACCIA UTENTE                               │
│  usb-blacklist-select  ──> Modifica /etc/usb-blacklist-watcher-pve/         │
│  (alias: usb-blacklist-select-pve)   blacklist.conf                         │
└─────────────────────────────────────┬───────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          SISTEMA DI PERSISTENZA                             │
│                /etc/usb-blacklist-watcher-pve/blacklist.conf                │
│                     (Permessi 600 - root:root - VENDOR:PRODUCT)             │
└─────────────────────────────────────┬───────────────────────────────────────┘
                                      │ (inotify)
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                             SERVIZIO DAEMON                                 │
│  usb-blacklist-watcher-pve.service (systemd) ──> usb-blacklist-watcher-pve  │
│    • inotifywait su /etc/pve/qemu-server/ e blacklist.conf                  │
│    • Risoluzione dinamica sysfs per passthrough via bus-port (es. 1-4.2)    │
│    • Enforcement automatico via `qm set <VMID> --delete usbN`              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Cronologia degli Step di Sviluppo (Round per Round)

---

### Round 1: Progettazione e Architettura Iniziale (`v1.0.0`)

#### Requisiti e scelte architetturali
1. **Identificazione dei Device**: Utilizzo primario del formato `VENDOR:PRODUCT` (es. `2e8a:0005` da `lsusb`), poiché indipendente dalla porta fisica USB a cui il dispositivo viene collegato.
2. **File di Stato Persistente**: Definito il percorso `/etc/usb-blacklist-watcher/blacklist.conf` protetto da permessi Unix `600` (`root:root`).
3. **Tool CLI Interattivo (`usb-blacklist-select`)**:
   - Lettura dei dispositivi connessi tramite `lsusb`.
   - Filtro automatico per hub generici e root hub Linux Foundation (`1d6b:0001`, `1d6b:0002`, `1d6b:0003`).
   - Modalità interattiva a selezione multipla con logica *toggle* (selezionare una voce già in blacklist la rimuove previa conferma).
   - Supporto alle flag non-interattive per scripting: `--add`, `--remove`, `--list`.
   - Enforcement immediato post-salvataggio.
4. **Watcher Daemon (`usb-blacklist-watcher`)**:
   - Esecuzione all'avvio (`enforce_all_confs`) per pulire le VM da eventuali entry residue.
   - Loop `inotifywait` per monitorare la directory dei conf QEMU (`/etc/pve/qemu-server`) e il file di blacklist.
   - Esecuzione di `qm set <VMID> --delete usbN` su qualsiasi riscontro.
5. **Struttura Pacchetto Debian (`.deb`)**:
   - File metadati `DEBIAN/control` con dipendenza dichiarata `inotify-tools`.
   - Script `postinst`: Creazione file predefinito con header, `systemctl daemon-reload`, `systemctl enable --now`.
   - Script `prerm`: Stop e disable del servizio prima della disinstallazione.
   - Script `postrm`: Distinzione tra `remove` (preserva la configurazione sul disco) e `purge` (elimina directory di configurazione).
   - Script di automazione build `build-deb.sh` con auto-versioning dal file `control`.

#### Risultato Round 1
Generato il primo pacchetto installabile `usb-blacklist-watcher_1.0.0_all.deb`.

---

### Round 2: Risoluzione del Bug di Inotify sui Symlink (`v1.0.1`)

#### Problema riscontrato sul campo
Dopo aver installato la v1.0.0 e aver aggiunto un USB alla blacklist, l'assegnazione dell'USB a una VM tramite GUI non veniva rilevata in tempo reale dal watcher. Tuttavia, riavviando manualmente il servizio con `systemctl restart usb-blacklist-watcher`, l'entry veniva immediatamente intercettata e rimossa.

#### Analisi della Root Cause
In Proxmox VE (che utilizza il filesystem FUSE di cluster `pmxcfs`), la directory `/etc/pve/qemu-server` **è un link simbolico (symlink)** verso `/etc/pve/nodes/<hostname>/qemu-server`.
Nel codice della v1.0.0, il comando era:
```bash
inotifywait ... "${QEMU_DIR}" "${blacklist_dir}"
```
Senza uno slash finale (`/`), `inotifywait` si agganciava direttamente al **symlink** e non alla directory reale di destinazione. Di conseguenza, le modifiche ai file `.conf` interni alla directory non generavano alcun evento inotify. Al contrario, `enforce_all_confs` funzionava al riavvio perché la wildcard Bash (`*.conf`) risolveva nativamente i symlink.

#### Soluzione Implementata
Modificato il path fornito ad `inotifywait` aggiungendo la trailing slash:
```bash
inotifywait ... "${QEMU_DIR}/" "${blacklist_dir}"
```
La barra finale forza il sistema ad effettuare la risoluzione del symlink, permettendo ad `inotifywait` di monitorare direttamente i file di configurazione reali delle VM.

#### Risultato Round 2
Rilasciato il pacchetto `usb-blacklist-watcher_1.0.1_all.deb` con reattività inotify ripristinata.

---

### Round 3: Mitigazione del Bypass via "USB Port Passthrough" (`v1.0.2`)

#### Problema riscontrato sul campo
Dall'interfaccia web di Proxmox (GUI), selezionando la modalità di passthrough **"Use USB Port"** invece di "Use USB Vendor/Device ID", Proxmox scrive nei file di configurazione delle VM una riga basata sulla topologia di porta fisica, come:
```ini
usb0: host=1-4.2
```
Poiché il watcher v1.0.1 cercava esclusivamente la stringa `host=2e8a:0005`, l'assegnazione via porta eludeva la blacklist.

#### Analisi della Root Cause
Non era possibile risolvere il problema semplicemente salvando le porte fisiche nella blacklist, poiché una porta fisica (es. `1-4.2`) potrebbe in futuro ospitare un dispositivo legittimo e non protetto. La blacklist doveva rimanere rigorosamente basata su `VENDOR:PRODUCT`.

La soluzione doveva consistere nel **tradurre in tempo reale** qualsiasi parametro `host=bus-port` presente nei file `.conf` nel corrispettivo `VENDOR:PRODUCT` del dispositivo in quel momento fisicamente inserito in quella porta.

#### Soluzione Implementata
Aggiornata la logica di estrazione delle chiavi USB in `usb-blacklist-watcher` e `usb-blacklist-select`.
Quando l'algoritmo incontra una riga `usbN: host=X-Y`:
1. Riconosce il formato porta fisica tramite Regex (`^[0-9]+-[0-9]+(\.[0-9]+)*$`).
2. Interroga in tempo reale il filesystem del kernel Linux `/sys/bus/usb/devices/X-Y/`:
   - Legge `/sys/bus/usb/devices/X-Y/idVendor`
   - Legge `/sys/bus/usb/devices/X-Y/idProduct`
3. Ricompone l'ID `VENDOR:PRODUCT` effettivo.
4. Confronta l'ID calcolato con la blacklist persistente e, se presente, innesca la cancellazione con `qm set <VMID> --delete usbN`.

```bash
elif [[ "${host_val}" =~ ^[0-9]+-[0-9]+(\.[0-9]+)*$ ]]; then
    local sysfs_dir="/sys/bus/usb/devices/${host_val}"
    if [ -f "${sysfs_dir}/idVendor" ] && [ -f "${sysfs_dir}/idProduct" ]; then
        local vendor product
        vendor=$(cat "${sysfs_dir}/idVendor")
        product=$(cat "${sysfs_dir}/idProduct")
        actual_id="${vendor,,}:${product,,}"
    fi
fi
```

#### Risultato Round 3
Rilasciato il pacchetto `usb-blacklist-watcher_1.0.2_all.deb` resistente al passthrough sia per ID dispositivo che per porta fisica.

---

### Round 4: Review Completa e Ottimizzazione (`v1.0.3` / `v1.0.4`)

Durante una code review approfondita del comportamento a runtime su nodi con molteplici VM (es. 18+ VM), sono stati identificati e risolti 5 problemi critici di performance, concorrenza e gestione degli errori:

#### 1. Implementazione di un Debounce Asincrono Reale con Killing dei Job Pendenti
- **Criticità originale**: La scrittura di un file `.conf` da parte di Proxmox genera molteplici eventi inotify ravvicinati (`MODIFY`, `CLOSE_WRITE`). Nel codice precedente, il debounce consisteva in un semplice `sleep 0.3` bloccante nel loop `while read`. Questo causava l'esecuzione in sequenza di 4 o più scansioni complete di tutte le VM per una singola modifica.
- **Soluzione**: Schedulazione asincrona in background con tracciamento del PID (`PENDING_PID`). Se arriva un nuovo evento prima del termine del debounce, il processo precedente viene eliminato con `kill` e riprogrammato. Quattro eventi rapidi generano ora **un'unica scansione**.
- **Adeguamento Shell**: Sostituita la pipe `inotifywait | while` con il costrutto *process substitution* `< <(inotifywait ...)`. Con la pipe standard, il `while` veniva eseguito in una subshell isolata e le variabili di stato dei PID non persistevano tra gli eventi.

#### 2. Deduplicazione delle Chiamate `get_blacklisted_usb_keys`
Eliminata la chiamata ridondante. `get_blacklisted_usb_keys()` viene eseguita una sola volta e il risultato viene riutilizzato sia per il controllo booleano che per il ciclo di cancellazione.

#### 3. Cattura dell'Exit Code di `qm set` senza Mascheramento da Pipe
Esecuzione diretta con cattura separata di output ed exit status (`qm_rc`), garantendo che eventuali errori di Proxmox QEMU vengano loggati.

#### 4. Caching della Blacklist in Memoria
La blacklist viene letta una sola volta per ciclo di enforcement e passata in memoria, eliminando decine di letture I/O disco ridondanti.

#### 5. Pulizia Nome Binario (`v1.0.4`)
Rimossa l'estensione `.sh` dal binario del daemon (`usb-blacklist-watcher.sh` -> `usb-blacklist-watcher`).

---

### Round 5: Rename Ufficiale a `usb-blacklist-watcher-pve` (`v1.1.0`)

#### Obiettivo
Uniformare il nome del progetto a `usb-blacklist-watcher-pve` per chiarire immediatamente l'ecosistema target (Proxmox VE), aggiornando tutti i componenti di sistema mantenendo piena retrocompatibilità per installazioni e script preesistenti.

#### Modifiche effettuate:
1. **Pacchetto Debian**:
   - `Package: usb-blacklist-watcher-pve`
   - Aggiunti header `Provides`, `Replaces`, `Conflicts` verso `usb-blacklist-watcher` per consentire un upgrade fluido con `dpkg -i` o `apt`.
2. **Directory di Configurazione e File di Stato**:
   - Spostata in `/etc/usb-blacklist-watcher-pve/blacklist.conf`.
   - Implementata in `postinst` la migrazione trasparente automatica della configurazione dalla vecchia cartella `/etc/usb-blacklist-watcher/` alla nuova.
3. **Servizio Systemd**:
   - Rinominato in `usb-blacklist-watcher-pve.service`.
   - Aggiunto `Alias=usb-blacklist-watcher.service` per non rompere comandi o script storici.
4. **Binari in `/usr/local/bin/`**:
   - Daemon primario: `usb-blacklist-watcher-pve`.
   - Symlink retrocompatibile: `usb-blacklist-watcher -> usb-blacklist-watcher-pve`.
   - Symlink di convenienza: `usb-blacklist-select-pve -> usb-blacklist-select`.
5. **Documentazione e Build Tooling**:
   - Aggiornato `build-deb.sh` per generare `usb-blacklist-watcher-pve_1.1.0_all.deb`.
   - Aggiornati `README.md`, `STRUTTURA.md` e questa relazione.

---

## 3. Matrice Comparativa delle Versioni

| Caratteristica / Fix | v1.0.0 | v1.0.1 | v1.0.2 | v1.0.3/4 | v1.1.0 (Attuale) |
|---|:---:|:---:|:---:|:---:|:---:|
| Intercettazione `VENDOR:PRODUCT` statico | ✅ | ✅ | ✅ | ✅ | ✅ |
| Tool CLI `usb-blacklist-select` | ✅ | ✅ | ✅ | ✅ | ✅ |
| Supporto Symlink `/etc/pve/qemu-server/` | ❌ | ✅ | ✅ | ✅ | ✅ |
| Traduzione Passthrough Bus-Port (`sysfs`) | ❌ | ❌ | ✅ | ✅ | ✅ |
| Debounce Reale Async (Job Kill) | ❌ | ❌ | ❌ | ✅ | ✅ |
| Process Substitution (Persistenza PID) | ❌ | ❌ | ❌ | ✅ | ✅ |
| Caching I/O Blacklist in Memoria | ❌ | ❌ | ❌ | ✅ | ✅ |
| Rilevamento Errori `qm set` | ❌ | ❌ | ❌ | ✅ | ✅ |
| Pacchetto `usb-blacklist-watcher-pve` | ❌ | ❌ | ❌ | ❌ | ✅ |
| Migrazione Automatica Vecchia Config | ❌ | ❌ | ❌ | ❌ | ✅ |

---

## 4. Struttura del Codice Finale

```
/home/user/Projects/usb-blacklist-watcher/
├── build/
│   └── usb-blacklist-watcher-pve/
│       ├── DEBIAN/
│       │   ├── control (Package: usb-blacklist-watcher-pve)
│       │   ├── postinst (Permessi 600, migrazione config, systemctl enable --now)
│       │   ├── prerm (Stop & disable servizio)
│       │   └── postrm (Purge vs Remove)
│       ├── usr/local/bin/
│       │   ├── usb-blacklist-select (Tool CLI interattivo)
│       │   ├── usb-blacklist-watcher-pve (Daemon watcher systemd)
│       │   ├── usb-blacklist-select-pve (Symlink a select)
│       │   └── usb-blacklist-watcher (Symlink retrocompatibile)
│       └── etc/
│           ├── systemd/system/
│           │   └── usb-blacklist-watcher-pve.service
│           └── usb-blacklist-watcher-pve/
│               └── blacklist.conf (File di stato predefinito)
├── build-deb.sh (Script di build automatizzato)
├── README.md (Manuale operativo)
├── STRUTTURA.md (Albero del progetto)
└── RELAZIONE_PROGETTO.md (Questa relazione)
```

---

## 5. Guida Rapida all'Uso e Manutenzione

### Installazione del Pacchetto Finale

```bash
dpkg -i usb-blacklist-watcher-pve_1.1.0_all.deb
```

### Configurazione della Blacklist

```bash
# Avvio interfaccia interattiva
usb-blacklist-select

# Oppure via CLI non-interattiva
usb-blacklist-select --add 2e8a:0005
usb-blacklist-select --remove 2e8a:0005
usb-blacklist-select --list
```

### Monitoraggio e Diagnostica

```bash
# Stato del servizio systemd
systemctl status usb-blacklist-watcher-pve

# Log in tempo reale
journalctl -u usb-blacklist-watcher-pve -f
```

---

## 6. Conclusioni

Con il rename a `usb-blacklist-watcher-pve` e il rilascio della versione `1.1.0`, il progetto raggiunge un livello di maturità completo per la produzione su ambienti Proxmox VE: robusto contro bypass, performante su installazioni con molte VM e retrocompatibile con tutte le configurazioni pregresse.
