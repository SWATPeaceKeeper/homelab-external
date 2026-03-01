# Design: Repo-Aufräumen, Security Hardening & Renovate Auto-Updates

Datum: 2026-03-01

## Kontext

Das Homelab-Repo ist der Einstiegspunkt zum Tailscale-Netzwerk. Ein Security-Audit
hat mehrere Härtungslücken aufgedeckt. Gleichzeitig soll die Repo-Struktur aufgeräumt
und ein automatischer Update-Mechanismus via Renovate eingeführt werden.

## Entscheidungen

- Docker-Socket an Headplane/Traefik: Risiko akzeptiert (read-only, Single-User-Setup)
- SSH Root-Login: Bleibt, wird aber gehärtet (Key-only + sshd-Hardening)
- ACL: SSH-Zugriff vom Hetzner-Server ins Heimnetz wird entfernt
- Konzeptdokumente: Aus dem Public Repo löschen
- Renovate: Konservativ (Patch automerge, Minor/Major als PR)
- Auto-Deploy: Cron-Job auf dem Server (kein GitHub Actions, keine GitHub Secrets)

---

## 1. Repo-Struktur

### Neue Struktur

```
bootstrap.sh
teardown.sh
cloud-init.yaml
CLAUDE.md
README.md                 # kurze Version mit Verweis auf docs/
renovate.json             # Renovate-Konfiguration
docs/
  README.md               # bisherige ausführliche Doku (verschoben)
  SETUP.md                # bisherige Setup-Anleitung (verschoben)
  plans/                  # Design-Dokumente
hetzner/
  .env.example
  docker-compose.yml
  scripts/
    headscale-setup.sh
    auto-update.sh        # Cron-Skript für Auto-Deploy
  headscale/
    config.yaml
    acl.json
    dns_records.json
  headplane/
    config.yaml
  traefik/
    traefik.yml
```

### Änderungen

- `README.md` → `docs/README.md` (ausführliche Version)
- `SETUP.md` → `docs/SETUP.md`
- Neues Root-`README.md`: Kurzbeschreibung + Links auf `docs/`
- `MONITORING_KONZEPT_V2.md` löschen (bleibt in Git-History)
- `VPN_KONZEPT_HEADSCALE_V1.md` löschen (bleibt in Git-History)
- `.gitignore` erweitern: `*.env`, `.env.*`, `!.env.example`

---

## 2. Security Hardening

### 2a) Docker Compose — alle Container

Jeder Container bekommt:

```yaml
security_opt:
  - no-new-privileges:true
cap_drop:
  - ALL
```

Explizites `cap_add` nur wo nötig:
- **tailscale**: `NET_ADMIN`, `SYS_MODULE`
- Alle anderen: keine Capabilities

Config-Mounts auf `:ro`:
- `headscale/config.yaml`, `acl.json`, `dns_records.json`
- `headplane/config.yaml`
- `traefik/traefik.yml` (bereits implizit über die statische Config)

### 2b) Traefik Hardening

**TLS-Konfiguration** in `traefik.yml`:

```yaml
tls:
  options:
    default:
      minVersion: VersionTLS12
      cipherSuites:
        - TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305
        - TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305
      sniStrict: true
```

**Security-Headers-Middleware** (global auf alle Router):

```yaml
http:
  middlewares:
    security-headers:
      headers:
        stsSeconds: 31536000
        stsIncludeSubdomains: true
        stsPreload: true
        frameDeny: true
        contentTypeNosniff: true
        referrerPolicy: "strict-origin-when-cross-origin"
        permissionsPolicy: "camera=(), microphone=(), geolocation=()"
```

Jeder Router in docker-compose.yml bekommt `security-headers` als Middleware.

**Rate-Limiting** für Auth-Endpunkte:

```yaml
http:
  middlewares:
    rate-limit:
      rateLimit:
        average: 50
        burst: 100
```

Auf Traefik-Dashboard und Headplane-Router anwenden.

**CORS einschränken** (Headscale):
- `accesscontrolallowheaders` von `*` auf `Content-Type, Authorization`

### 2c) SSH Hardening

Neuer Block in `cloud-init.yaml` (`write_files`):

```yaml
- path: /etc/ssh/sshd_config.d/hardening.conf
  content: |
    PermitRootLogin prohibit-password
    MaxAuthTries 3
    LoginGraceTime 20
    AllowAgentForwarding no
    AllowTcpForwarding no
    X11Forwarding no
```

### 2d) ACL

Port 22 aus der `server`-Gruppe in `acl.json` entfernen.
Nur Monitoring-Ports bleiben: 80, 443, 3000, 8080, 8123, 9090, 9100.

### 2e) Secrets aus Logs entfernen

- `bootstrap.sh`: Traefik-Passwort nicht mehr im Klartext ausgeben.
  Stattdessen: `"Passwort: siehe /opt/homelab-repo/hetzner/.env"`
- `headscale-setup.sh`: API-Key-Ausgabe entfernen, nur Erfolgs-/Fehlermeldung.

### 2f) DNS-Fallback

Headscale `config.yaml`:

```yaml
nameservers:
  global:
    - 1.1.1.1
    - 9.9.9.9
```

---

## 3. Image Pinning & Renovate

### 3a) Image Pinning

| Service | Alt | Neu |
|---------|-----|-----|
| headscale | `:stable` | `:v0.28.0` |
| headplane | `:0.6.2-beta.5` | `:v0.6.2` |
| tailscale | `:stable` | `:v1.94.2` |
| ntfy | `:latest` | `:v2.17.0` |
| healthchecks | `:latest` | `:v4.0` |
| uptime-kuma | `:2` | `:2.1.3` |
| traefik | `:v3.6` | `:v3.6.9` |
| postgres (beide) | `:17-alpine` | `:17.9-alpine` |

### 3b) Renovate-Konfiguration

Datei: `renovate.json`

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "config:recommended",
    "group:allNonMajor"
  ],
  "schedule": ["after 9am on Monday"],
  "labels": ["dependencies"],
  "packageRules": [
    {
      "description": "Automerge patch updates",
      "matchManagers": ["docker-compose"],
      "matchUpdateTypes": ["patch"],
      "automerge": true
    },
    {
      "description": "Pin postgres to major 17",
      "matchManagers": ["docker-compose"],
      "matchPackageNames": ["postgres"],
      "allowedVersions": "/^17\\./"
    }
  ]
}
```

Renovate erkennt `docker-compose.yml` nativ und erstellt PRs für Image-Updates.

### 3c) Auto-Deploy via Cron

Skript: `hetzner/scripts/auto-update.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="/opt/homelab-repo"
COMPOSE_DIR="${REPO_DIR}/hetzner"
LOG_FILE="/var/log/homelab-update.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

log "Starting auto-update"

cd "$REPO_DIR"
git fetch origin main

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)

if [ "$LOCAL" = "$REMOTE" ]; then
    log "Already up to date"
    exit 0
fi

log "Pulling changes: ${LOCAL:0:7} -> ${REMOTE:0:7}"
git pull origin main

cd "$COMPOSE_DIR"
docker compose pull
docker compose up -d --remove-orphans

log "Update complete"
```

Einrichtung via `cloud-init.yaml`:
- Skript wird mit dem Repo deployed (liegt in `hetzner/scripts/`)
- Cron-Eintrag: Dienstag 12:00 UTC (einige Stunden nach Renovate am Montag)

```yaml
- path: /etc/cron.d/homelab-update
  content: |
    0 12 * * 2 root /opt/homelab-repo/hetzner/scripts/auto-update.sh
```

---

## 4. Kleinere Optimierungen

### Fehlende Healthchecks ergänzen

**healthchecks** (Service):
```yaml
healthcheck:
  test: ["CMD-SHELL", "curl -f http://localhost:8000/api/v3/status/ || exit 1"]
  interval: 30s
  timeout: 5s
  retries: 5
  start_period: 30s
```

**uptime-kuma**:
```yaml
healthcheck:
  test: ["CMD-SHELL", "curl -f http://localhost:3001/api/status-page/heartbeat || exit 1"]
  interval: 30s
  timeout: 5s
  retries: 5
```

**tailscale**:
```yaml
healthcheck:
  test: ["CMD", "tailscale", "status"]
  interval: 30s
  timeout: 5s
  retries: 5
```

### Headplane Upgrade

v0.6.2-beta.5 → v0.6.2 (stable). Keine Config-Änderungen nötig.
CLAUDE.md-Referenz aktualisieren.

### Headscale Healthcheck-Parameter

Explizite Werte ergänzen (aktuell nur `test`, keine Intervalle):

```yaml
healthcheck:
  test: ["CMD", "headscale", "health"]
  interval: 30s
  timeout: 5s
  retries: 5
  start_period: 15s
```

### CLAUDE.md aktualisieren

Alle Änderungen reflektieren: neue Repo-Struktur, Security-Maßnahmen,
Renovate, Auto-Deploy, aktualisierte Versionen.

---

## Nicht im Scope

- Backup-Strategie für `/opt/homelab-data/` (separates Projekt)
- Deploy-User statt Root (bewusst beibehalten)
- Docker-Socket-Proxy (Risiko akzeptiert)
- Separate PostgreSQL-Passwörter (bewusste Vereinfachung)
- Image-Digest-Pinning (Renovate mit Versions-Tags reicht)
