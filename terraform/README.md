# 🏠 Homelab External Infrastructure

Terraform-basierte Infrastruktur für den externen Teil des Homelab-Setups auf Hetzner Cloud.

## 📋 Übersicht

Dieses Repository erstellt und verwaltet:

| Dienst | URL | Beschreibung |
|--------|-----|--------------|
| **Headscale** | headscale.homelab.robinwerner.net | VPN Coordination Server |
| **Headplane** | vpn.homelab.robinwerner.net | VPN Web-UI |
| **Uptime Kuma** | uptime.homelab.robinwerner.net | Uptime Monitoring |
| **ntfy** | ntfy.homelab.robinwerner.net | Push Notifications |
| **Healthchecks** | hc.homelab.robinwerner.net | Cronjob Monitoring |

## 🏗️ Architektur

```
┌─────────────────────────────────────────────────────────────┐
│                    HETZNER vSERVER                          │
│                    (cx22 - ~4.50€/Monat)                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────┐  ┌──────────┐  ┌───────────┐  ┌────────────┐  │
│  │Headscale│  │Headplane │  │Uptime Kuma│  │    ntfy    │  │
│  └────┬────┘  └────┬─────┘  └─────┬─────┘  └─────┬──────┘  │
│       │            │              │              │         │
│       └────────────┴──────────────┴──────────────┘         │
│                           │                                 │
│                    ┌──────┴──────┐                          │
│                    │   Traefik   │ (Reverse Proxy + SSL)    │
│                    └─────────────┘                          │
│                           │                                 │
│              ┌────────────┴────────────┐                   │
│              ▼                         ▼                    │
│         :80/:443                   :3478/udp                │
│         (HTTPS)                    (DERP/STUN)              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                           │
                           │ Tailnet (VPN)
                           ▼
                    ┌──────────────┐
                    │   HOMELAB    │
                    │  10.0.0.0/24 │
                    └──────────────┘
```

## 🚀 Quick Start

### Voraussetzungen

1. **Terraform** >= 1.5.0 installiert
2. **Hetzner Cloud Account** mit API-Token
3. **Cloudflare Account** mit API-Token (DNS Edit Permission)

### 1. Repository klonen

```bash
git clone git@github.com:DEIN_USERNAME/homelab-external.git
cd homelab-external
```

### 2. Secrets konfigurieren

```bash
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars editieren und Werte eintragen
```

### 3. Deployment

```bash
# Initialisieren
terraform init

# Plan prüfen
terraform plan

# Anwenden
terraform apply
```

### 4. Post-Deployment

Nach dem ersten Deployment:

```bash
# SSH zum Server
ssh root@$(terraform output -raw server_ipv4)

# Headscale Namespace erstellen
docker exec headscale headscale namespaces create homelab

# API-Key generieren (für Headplane)
docker exec headscale headscale apikeys create --expiration 365d

# API-Key in /opt/homelab/.env eintragen
nano /opt/homelab/.env  # HEADSCALE_API_KEY=...

# Container neu starten
cd /opt/homelab && docker compose up -d
```

## 🔧 GitHub Actions (optional)

### Secrets einrichten

Gehe zu **Settings → Secrets and variables → Actions** und füge hinzu:

| Secret | Beschreibung |
|--------|--------------|
| `HETZNER_TOKEN` | Hetzner Cloud API Token |
| `CLOUDFLARE_API_TOKEN` | Cloudflare API Token |
| `CLOUDFLARE_ZONE_ID` | Zone ID der Domain |

### Environments

Erstelle zwei Environments unter **Settings → Environments**:

1. **production** - für `terraform apply`
2. **destroy-production** - für `terraform destroy` (mit Approval)

## 📁 Struktur

```
.
├── .github/
│   └── workflows/
│       └── terraform.yml     # GitHub Actions Pipeline
├── main.tf                   # Hauptkonfiguration
├── variables.tf              # Variablen-Definitionen
├── outputs.tf                # Output-Werte
├── versions.tf               # Provider-Versionen
├── cloud-init.yaml           # Server-Initialisierung
├── terraform.tfvars.example  # Beispiel-Variablen
└── README.md
```

## 🔐 Sicherheit

- Alle Dienste hinter Traefik mit automatischem Let's Encrypt
- SSH nur mit Key-Auth (Passwort deaktiviert)
- Fail2ban für Brute-Force-Schutz
- UFW Firewall mit minimalen offenen Ports
- Headscale ACLs für Zugriffskontrolle

## 📊 Kosten

| Ressource | Kosten/Monat |
|-----------|--------------|
| Hetzner CX22 | ~4.50€ |
| **Gesamt** | **~4.50€** |

## 🔗 Verbundene Repositories

- `homelab-nuc` - NUC Docker-Konfiguration (lokal)
- `homelab-docs` - Dokumentation

## 📝 Wartung

### Server-Updates

```bash
ssh root@SERVER_IP
apt update && apt upgrade -y
cd /opt/homelab && docker compose pull && docker compose up -d
```

### Logs prüfen

```bash
# Traefik Logs
docker logs traefik -f

# Headscale Logs
docker logs headscale -f
```

### Backup

Der wichtigste State liegt in:
- `/opt/homelab/headscale/data/` - Headscale Datenbank
- `/opt/homelab/uptime-kuma/` - Uptime Kuma Daten

## 📚 Dokumentation

- [Headscale Docs](https://headscale.net/stable/)
- [Traefik Docs](https://doc.traefik.io/traefik/)
- [Uptime Kuma](https://github.com/louislam/uptime-kuma)
- [ntfy](https://ntfy.sh/docs/)

---

*Erstellt: Januar 2026*
