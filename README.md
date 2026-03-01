# Homelab External

Selbst-gehostete Infrastruktur auf einem Hetzner vServer (~5 EUR/Monat). VPN, Monitoring und Push-Notifications — provisioniert mit einem einzigen Shell Script.

## Services

| Dienst | Beschreibung |
|--------|-------------|
| [Headscale](https://github.com/juanfont/headscale) | VPN Coordination Server (selbst-gehostete Tailscale Alternative) |
| [Headplane](https://github.com/tale/headplane) | Web-UI für Headscale |
| [Traefik](https://traefik.io/) | Reverse Proxy mit automatischen Let's Encrypt Zertifikaten |
| [Uptime Kuma](https://github.com/louislam/uptime-kuma) | Uptime Monitoring & Status Page |
| [ntfy](https://ntfy.sh/) | Push-Notification Server |
| [Healthchecks](https://healthchecks.io/) | Cronjob Monitoring |

## Architektur

```
                        ┌─────────────────────────────────────────┐
                        │           Hetzner vServer (CX23)        │
                        │                                         │
Internet ──► Traefik ──►│  headscale    uptime-kuma    ntfy       │
             (443/80)   │  headplane    healthchecks              │
                        │                                         │
                        │  ┌─────────────┐  ┌──────────────────┐  │
                        │  │ PostgreSQL   │  │ PostgreSQL       │  │
                        │  │ (Headscale)  │  │ (Healthchecks)   │  │
                        │  └─────────────┘  └──────────────────┘  │
                        │                                         │
                        │  Tailscale Client ◄──► Homelab (VPN)    │
                        └─────────────────────────────────────────┘
```

- **Traefik** routet alle HTTPS-Anfragen an die Services (via Docker Labels)
- **Tailscale Client** verbindet den Server per VPN ins lokale Homelab
- **Uptime Kuma** überwacht über den VPN-Tunnel die internen Dienste

## Quick Start

```bash
# Voraussetzungen: hcloud, curl, jq, openssl
export HCLOUD_TOKEN="..."
export CLOUDFLARE_API_TOKEN="..."
export CLOUDFLARE_ZONE_ID="..."

./bootstrap.sh    # Erstellt alles (~3-5 Min)
./teardown.sh     # Löscht alles
```

Detaillierte Anleitung: [SETUP.md](SETUP.md)

## Repo-Struktur

```
bootstrap.sh              Provisioning (lokal ausführen)
teardown.sh               Teardown (lokal ausführen)
cloud-init.yaml           Server-Grundkonfiguration
hetzner/
  docker-compose.yml      Alle Services
  .env.example            Environment-Template
  scripts/
    headscale-setup.sh    Headscale Bootstrap (auf Server)
  traefik/traefik.yml     Traefik Konfiguration
  headscale/              Headscale Config + ACL
  headplane/              Headplane Config
```

## Kosten

| Posten | Monat |
|--------|-------|
| Hetzner CX23 (Falkenstein) | ~5 EUR |
| Cloudflare DNS | kostenlos |
| Let's Encrypt SSL | kostenlos |
