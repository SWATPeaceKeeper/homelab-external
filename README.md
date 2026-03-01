# Homelab External

Selbst-gehostete Infrastruktur auf einem Hetzner vServer (~5 EUR/Monat).

VPN (Headscale), Monitoring (Uptime Kuma, Healthchecks), Push-Notifications (ntfy) — provisioniert mit einem einzigen Shell Script.

## Quick Start

```bash
export HCLOUD_TOKEN="..." CLOUDFLARE_API_TOKEN="..." CLOUDFLARE_ZONE_ID="..."
./bootstrap.sh    # Erstellt alles (~3-5 Min)
./teardown.sh     # Löscht alles
```

## Dokumentation

- [Ausführliche Übersicht](docs/README.md)
- [Setup-Anleitung](docs/SETUP.md)
