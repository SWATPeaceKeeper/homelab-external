# Homelab External - Setup Guide

Diese Anleitung beschreibt das vollständige Setup des Homelab External Servers auf Hetzner.

## Übersicht

```
┌─────────────────────────────────────────────────────────────────┐
│                    Hetzner vServer                               │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                     Traefik                              │    │
│  │              (Reverse Proxy + SSL)                       │    │
│  │         Port 80/443 → Let's Encrypt                      │    │
│  └──────────────────────┬──────────────────────────────────┘    │
│                         │                                        │
│    ┌────────────────────┼────────────────────┐                  │
│    │                    │                    │                  │
│    ▼                    ▼                    ▼                  │
│ ┌──────────┐     ┌──────────────┐     ┌─────────────┐          │
│ │Headscale │     │ Uptime Kuma  │     │    NTFY     │          │
│ │(VPN)     │     │ (Monitoring) │     │(Push Notif) │          │
│ └────┬─────┘     └──────────────┘     └─────────────┘          │
│      │                                                          │
│ ┌────┴─────┐     ┌──────────────┐     ┌─────────────┐          │
│ │Headplane │     │ Healthchecks │     │  PostgreSQL │          │
│ │(VPN UI)  │     │ (Cron Mon.)  │     │  (Database) │          │
│ └──────────┘     └──────────────┘     └─────────────┘          │
│                                                                  │
│ ┌──────────────────────────────────────────────────────────┐    │
│ │                    Tailscale Client                       │    │
│ │            (Verbindung zum Homelab über VPN)              │    │
│ └──────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

## Voraussetzungen

- Hetzner Cloud Account mit API Token
- Cloudflare Account mit API Token (für DNS)
- Domain bei Cloudflare (z.B. robinwerner.net)
- GitHub Account (für Repository und Actions)
- SSH Key für Server-Zugang

## Teil 1: GitHub Secrets konfigurieren

Diese Secrets müssen in GitHub unter **Settings → Secrets and variables → Actions** angelegt werden:

| Secret | Beschreibung | Wie erstellen |
|--------|--------------|---------------|
| `HETZNER_TOKEN` | Hetzner Cloud API Token | Hetzner Console → Security → API Tokens |
| `CLOUDFLARE_API_TOKEN` | Cloudflare API Token | Cloudflare Dashboard → API Tokens |
| `CLOUDFLARE_ZONE_ID` | Zone ID deiner Domain | Cloudflare Dashboard → Domain → Overview (rechte Seite) |
| `HETZNER_S3_ACCESS_KEY` | Object Storage Access Key | Hetzner Console → Object Storage → Credentials |
| `HETZNER_S3_SECRET_KEY` | Object Storage Secret Key | Hetzner Console → Object Storage → Credentials |
| `REPO_SSH_URL` | Git SSH URL | z.B. `git@github.com:username/repo.git` |
| `SSH_PUBLIC_KEY` | Dein SSH Public Key | `cat ~/.ssh/id_rsa.pub` |

## Teil 2: Infrastruktur mit Terraform erstellen

### Option A: Über GitHub Actions (empfohlen)

1. Push zu `main` Branch mit Änderungen in `terraform/`
2. GitHub Action führt `terraform plan` aus
3. Bei direktem Push zu `main`: Auto-Apply
4. Bei Pull Request: Nur Plan, Apply nach Merge

### Option B: Manuell

```bash
cd terraform

# Backend initialisieren
export AWS_ACCESS_KEY_ID="<hetzner-s3-access-key>"
export AWS_SECRET_ACCESS_KEY="<hetzner-s3-secret-key>"
terraform init

# Variablen setzen
export TF_VAR_hetzner_token="<token>"
export TF_VAR_cloudflare_api_token="<token>"
export TF_VAR_cloudflare_zone_id="<zone-id>"
export TF_VAR_repo_ssh_url="git@github.com:user/repo.git"
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_rsa.pub)"

# Plan prüfen
terraform plan

# Anwenden
terraform apply
```

### Nach dem Apply

Terraform gibt wichtige Informationen aus:
- Server IP
- SSH Command
- Deploy Key (für GitHub)
- Nächste Schritte

**Wichtig:** Füge den Deploy Key zum GitHub Repository hinzu:
1. GitHub → Repository → Settings → Deploy Keys
2. "Add deploy key"
3. Key einfügen (aus Terraform Output)
4. Read-only aktivieren

## Teil 3: Secrets generieren

Auf deinem lokalen Rechner die Secrets generieren:

```bash
# 1. PostgreSQL Passwort (32 Zeichen hex)
openssl rand -hex 16
# Beispiel: a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6

# 2. Cookie Secret für Headplane (MUSS exakt 32 Zeichen sein!)
openssl rand -hex 16
# Beispiel: f7e6d5c4b3a2918273645566778899aa

# 3. Healthchecks Secret (50 Zeichen hex)
openssl rand -hex 25
# Beispiel: 1234567890abcdef...

# 4. Traefik Dashboard Passwort
htpasswd -nb admin DEIN_SICHERES_PASSWORT
# Beispiel: admin:$apr1$xyz...
```

**Notiere diese Werte sicher!** Du brauchst sie gleich.

## Teil 4: Konfiguration auf Server deployen

### 4.1 Zum Server verbinden

```bash
ssh root@<server-ip>
```

### 4.2 Repository klonen und Symlinks erstellen

```bash
# Deploy Key wurde von Cloud-Init bereits eingerichtet
# Repository klonen
git clone git@github.com:dein-user/homelab-external.git /opt/homelab-repo

# Symlink für Arbeitsverzeichnis erstellen
ln -s /opt/homelab-repo/hetzner /opt/homelab

# Symlink für Daten erstellen (docker-compose nutzt ./data/)
ln -s /opt/homelab-data /opt/homelab/data

# Ins Arbeitsverzeichnis wechseln
cd /opt/homelab
```

### 4.3 Verzeichnisstruktur prüfen

```bash
ls -la /opt/homelab/
# Sollte zeigen: traefik/, headscale/, headplane/, data -> /opt/homelab-data

ls -la /opt/homelab-data/
# Sollte zeigen: traefik/, headscale/, postgres/, uptime-kuma/, etc.
```

**Struktur auf dem Server:**
```
/opt/homelab-repo/                    # Git Repository (komplett)
├── .github/
├── terraform/
└── hetzner/                          # ← Configs

/opt/homelab -> /opt/homelab-repo/hetzner    # Symlink (Arbeitsverzeichnis)

/opt/homelab-data/                    # Persistente Daten (NICHT in Git!)
├── traefik/certs/
├── headscale/
├── postgres/
└── ...

/opt/homelab/data -> /opt/homelab-data       # Symlink (für docker-compose)
```

### 4.4 .env Datei erstellen

```bash
cp .env.example .env
nano .env
```

Fülle die Werte aus:

```bash
# Domain
DOMAIN=robinwerner.net
SUBDOMAIN_PREFIX=homelab-external

# Traefik (htpasswd Ausgabe von oben - WICHTIG: $ mit $$ escapen!)
TRAEFIK_DASHBOARD_AUTH=admin:$$apr1$$xyz...

# PostgreSQL (openssl rand -hex 16 von oben)
# HINWEIS: Wird automatisch an Headscale übergeben, keine manuelle Config-Änderung nötig!
POSTGRES_PASSWORD=a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6

# Headscale (wird später ausgefüllt)
HEADSCALE_API_KEY=

# Tailscale (wird später ausgefüllt)
TS_AUTHKEY=

# Healthchecks (openssl rand -hex 25 von oben)
HEALTHCHECKS_SECRET=1234567890abcdef...

# Timezone
TZ=Europe/Berlin
```

**Hinweis zu Secrets:**
- **PostgreSQL Passwort**: Wird automatisch via Environment Variable an Headscale übergeben
- **Headplane Cookie Secret**: Wurde bereits von Cloud-Init generiert in `./data/secrets/cookie_secret`

### 4.5 Cookie Secret prüfen (optional)

Das Cookie Secret für Headplane wurde von Cloud-Init automatisch generiert:

```bash
# Prüfen ob vorhanden
cat /opt/homelab-data/secrets/cookie_secret
# Sollte 32 Zeichen zeigen

# Falls nicht vorhanden, manuell erstellen:
mkdir -p /opt/homelab-data/secrets
openssl rand -hex 16 > /opt/homelab-data/secrets/cookie_secret
chmod 600 /opt/homelab-data/secrets/cookie_secret
```

### 4.6 Traefik Zertifikat-Datei prüfen

Die acme.json wurde bereits von Cloud-Init erstellt:

```bash
# Prüfen ob vorhanden und korrekte Berechtigungen
ls -la /opt/homelab-data/traefik/certs/acme.json
# Sollte zeigen: -rw------- (600)

# Falls nicht vorhanden oder falsche Berechtigungen:
touch /opt/homelab-data/traefik/certs/acme.json
chmod 600 /opt/homelab-data/traefik/certs/acme.json
```

## Teil 5: Services starten

### 5.1 Docker Compose starten

```bash
# Alle Services starten
docker compose up -d

# Logs beobachten
docker compose logs -f

# Oder einzelne Services:
docker compose logs -f traefik
docker compose logs -f headscale
```

### 5.2 Headscale User erstellen

**Wichtig:** Warte bis Headscale vollständig gestartet ist!

```bash
# User für dein Homelab erstellen
docker exec headscale headscale users create homelab

# Prüfen ob User erstellt wurde
docker exec headscale headscale users list
```

### 5.3 Headscale API Key für Headplane generieren

```bash
# API Key erstellen (1 Jahr gültig)
docker exec headscale headscale apikeys create --expiration 365d
```

Kopiere den Key und trage ihn in `.env` ein:

```bash
nano .env
# HEADSCALE_API_KEY=<der-key-von-oben>
```

Dann Headplane neu starten:

```bash
docker compose restart headplane
```

### 5.4 Tailscale Client verbinden

```bash
# Pre-Auth Key für den Server erstellen
docker exec headscale headscale preauthkeys create --user homelab --expiration 24h
```

Kopiere den Key und trage ihn in `.env` ein:

```bash
nano .env
# TS_AUTHKEY=<der-preauth-key>
```

Dann Tailscale neu starten:

```bash
docker compose restart tailscale
```

Prüfen ob verbunden:

```bash
docker exec headscale headscale nodes list
# Sollte "hetzner-server" zeigen
```

## Teil 6: Services einrichten

### 6.1 URLs prüfen

Alle Services sollten jetzt erreichbar sein:

| Service | URL |
|---------|-----|
| Traefik Dashboard | https://traefik.homelab-external.robinwerner.net |
| Headscale | https://headscale.homelab-external.robinwerner.net |
| Headplane (VPN UI) | https://vpn.homelab-external.robinwerner.net |
| Uptime Kuma | https://uptime.homelab-external.robinwerner.net |
| NTFY | https://ntfy.homelab-external.robinwerner.net |
| Healthchecks | https://hc.homelab-external.robinwerner.net |

### 6.2 Uptime Kuma einrichten

1. Öffne https://uptime.homelab-external.robinwerner.net
2. Erstelle Admin-Account
3. Füge Monitors für deine Services hinzu

### 6.3 NTFY einrichten

```bash
# Admin User erstellen
docker exec -it ntfy ntfy user add --role=admin admin
```

### 6.4 Healthchecks einrichten

1. Öffne https://hc.homelab-external.robinwerner.net
2. Erstelle Admin-Account über CLI:

```bash
docker exec -it healthchecks ./manage.py createsuperuser
```

## Teil 7: Lokale Clients verbinden

### macOS/Linux mit Tailscale

```bash
# Mit Headscale verbinden
tailscale up --login-server=https://headscale.homelab-external.robinwerner.net

# Browser öffnet sich für Registrierung
# Oder manuell: URL aus Terminal-Output kopieren
```

Dann auf dem Server genehmigen:

```bash
# Neue Nodes anzeigen
docker exec headscale headscale nodes list

# Node genehmigen (falls --register-node URL genutzt)
docker exec headscale headscale nodes register --user homelab --key nodekey:abc123...
```

### Windows mit Tailscale

1. Tailscale installieren: https://tailscale.com/download/windows
2. In der Taskleiste: Rechtsklick → "Log in to a different server"
3. URL eingeben: `https://headscale.homelab-external.robinwerner.net`

### iOS/Android

1. Tailscale App installieren
2. In Settings: "Use an alternate coordination server"
3. URL: `https://headscale.homelab-external.robinwerner.net`

## Troubleshooting

### Traefik zeigt 404

```bash
# Prüfen ob Router registriert sind
docker compose logs traefik | grep -i "router"

# Dashboard öffnen für Details
# https://traefik.homelab-external.robinwerner.net
```

### Headscale startet nicht

```bash
# Logs prüfen
docker compose logs headscale

# Häufige Probleme:
# - PostgreSQL noch nicht bereit → docker compose restart headscale
# - Config Syntax Fehler → config.yaml prüfen
# - Falsches DB Passwort → .env und config.yaml vergleichen
```

### Zertifikate werden nicht ausgestellt

```bash
# Let's Encrypt Logs
docker compose logs traefik | grep -i "acme"

# Prüfen ob Port 80 erreichbar
curl -I http://headscale.homelab-external.robinwerner.net

# acme.json Berechtigungen
ls -la /opt/homelab-data/traefik/certs/
# Muss 600 sein!
```

### Tailscale verbindet nicht

```bash
# Tailscale Logs
docker compose logs tailscale

# Ist Headscale erreichbar?
curl https://headscale.homelab-external.robinwerner.net/health

# Pre-Auth Key abgelaufen?
# → Neuen erstellen und in .env eintragen
```

### PostgreSQL Connection Refused

```bash
# PostgreSQL Status prüfen
docker compose ps postgres

# PostgreSQL Logs
docker compose logs postgres

# Manuell verbinden
docker exec -it postgres psql -U headscale -d headscale
```

## Backup & Restore

### Backup erstellen

```bash
# Daten-Verzeichnis sichern (NICHT das Git-Repo, nur die Daten!)
cd /opt
tar -czvf backup-$(date +%Y%m%d).tar.gz homelab-data/

# Oder nur PostgreSQL:
docker exec postgres pg_dump -U headscale headscale > backup-db-$(date +%Y%m%d).sql

# .env Datei separat sichern (enthält Secrets!)
cp /opt/homelab/.env /root/backup-env-$(date +%Y%m%d)
```

### Restore

```bash
# Daten wiederherstellen
cd /opt
tar -xzvf backup-20240101.tar.gz

# PostgreSQL restore
cat backup-db-20240101.sql | docker exec -i postgres psql -U headscale headscale
```

## Updates

### Container aktualisieren

```bash
cd /opt/homelab

# Neueste Images ziehen
docker compose pull

# Container neu starten
docker compose up -d

# Alte Images entfernen
docker image prune -f
```

### Config-Änderungen deployen

```bash
# Git Repository aktualisieren
cd /opt/homelab-repo
git pull

# Änderungen sind sofort in /opt/homelab/ verfügbar (Symlink)
cd /opt/homelab

# Betroffene Services neu starten
docker compose restart headscale  # z.B. nach ACL-Änderungen
```

## Checkliste

- [ ] GitHub Secrets konfiguriert
- [ ] Terraform erfolgreich ausgeführt
- [ ] Deploy Key zu GitHub hinzugefügt
- [ ] Repository geklont nach /opt/homelab-repo
- [ ] Symlink /opt/homelab erstellt
- [ ] Symlink /opt/homelab/data erstellt
- [ ] Secrets generiert (POSTGRES_PASSWORD, HEALTHCHECKS_SECRET, TRAEFIK_DASHBOARD_AUTH)
- [ ] .env Datei erstellt und ausgefüllt
- [ ] Cookie Secret vorhanden (/opt/homelab-data/secrets/cookie_secret)
- [ ] acme.json vorhanden mit Berechtigung 600
- [ ] `docker compose up -d` erfolgreich
- [ ] Headscale User "homelab" erstellt
- [ ] Headscale API Key generiert und in .env eingetragen
- [ ] Headplane neu gestartet
- [ ] Tailscale Pre-Auth Key generiert und in .env eingetragen
- [ ] Tailscale neu gestartet und verbunden
- [ ] Alle URLs erreichbar
- [ ] NTFY Admin erstellt
- [ ] Healthchecks Admin erstellt
- [ ] Erste lokale Clients verbunden
