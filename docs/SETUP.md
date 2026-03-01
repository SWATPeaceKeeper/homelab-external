# Homelab External - Setup Anleitung

Dieses Setup verbindet einen Hetzner vServer mit deinem Heimnetzwerk per VPN.
Der Hetzner Server hostet Monitoring-Tools, die deine Heimnetz-Geräte überwachen.
Gleichzeitig kannst du von unterwegs (Mac, Handy) über das VPN auf dein Heimnetz
zugreifen — inklusive Pi-hole Werbeblocker, als wärst du zuhause.

## Architektur

```
                          ┌─────────────────────────────────────┐
                          │        Hetzner vServer (CX23)       │
                          │                                     │
    Internet ──► Traefik ─┤  Headscale    Uptime Kuma    ntfy  │
                 (443/80) │  Headplane    Healthchecks          │
                          │                                     │
                          │  Tailscale Client                   │
                          └───────────┬─────────────────────────┘
                                      │ VPN-Tunnel
                          ┌───────────┴─────────────────────────┐
                          │    Heimnetz (10.10.10.0/24)         │
                          │                                     │
  Mac / Handy ··· VPN ··· │  NUC (Subnet Router + Exit Node)   │
   (unterwegs)            │  Pi-hole · Server · IoT · ...      │
                          └─────────────────────────────────────┘
```

### Routing

| Quelle | Ziel | Weg |
|--------|------|-----|
| Hetzner Server | Internet | Direkt (kein VPN) |
| Hetzner Server | Heimnetz (10.10.10.0/24) | VPN → Subnet Route via NUC |
| Mac / Handy (unterwegs) | Heimnetz | VPN → Subnet Route via NUC |
| Mac / Handy (unterwegs) | Internet | VPN → Exit Node (NUC) → Pi-hole → Internet |

Der Hetzner Server nutzt **keinen Exit Node** — er geht direkt ins Internet.
Nur mobile Endgeräte routen ihren gesamten Traffic über den NUC als Exit Node,
um vom Pi-hole Werbeblocker zu profitieren.

---

## Voraussetzungen

### Tools installieren

```bash
# macOS
brew install hcloud jq openssl

# Ubuntu/Debian
apt install hcloud-cli jq openssl
```

### API Tokens besorgen

1. **Hetzner Cloud API Token** (Read & Write):
   `https://console.hetzner.cloud` → Projekt → Security → API Tokens

2. **Cloudflare API Token** (Zone DNS Edit):
   `https://dash.cloudflare.com/profile/api-tokens` → Create Custom Token

3. **Cloudflare Zone ID**:
   `https://dash.cloudflare.com` → Domain → Rechte Sidebar → Zone ID

### SSH Key

```bash
# Falls kein Key existiert:
ssh-keygen -t ed25519 -C "homelab-external"
```

---

## Phase 1: Hetzner Server aufsetzen

### 1. Tokens setzen

```bash
export HCLOUD_TOKEN="hc_xxx..."
export CLOUDFLARE_API_TOKEN="xxx..."
export CLOUDFLARE_ZONE_ID="xxx..."
```

### 2. Bootstrap ausführen

```bash
./bootstrap.sh
```

Das Script macht automatisch:
- SSH Key zu Hetzner hochladen
- Firewall erstellen (SSH, HTTP, HTTPS, DERP)
- Server mit Cloud-Init erstellen (Docker, UFW, fail2ban)
- 5 DNS A-Records bei Cloudflare anlegen
- Repo klonen und `.env` generieren
- `docker compose up -d`
- Headscale User + API Key erstellen

Dauer: ca. 3-5 Minuten.

### 3. Manuelle Schritte nach Bootstrap

Die SSH-Verbindung und das Traefik-Dashboard-Passwort werden am Ende
von `bootstrap.sh` ausgegeben.

```bash
# ntfy Admin-User erstellen
ssh -i ~/.ssh/id_ed25519 root@<SERVER_IP> \
  'docker exec -it ntfy ntfy user add --role=admin admin'

# Healthchecks Superuser erstellen
ssh -i ~/.ssh/id_ed25519 root@<SERVER_IP> \
  'docker exec healthchecks ./manage.py createsuperuser --noinput --email admin@example.com'

# Healthchecks Passwort setzen (oder via Web-UI "Forgot Password")
ssh -i ~/.ssh/id_ed25519 root@<SERVER_IP> \
  'docker exec healthchecks ./manage.py shell -c "
from django.contrib.auth.models import User
u = User.objects.first()
u.set_password(\"DEIN_PASSWORT\")
u.save()
"'
```

### 4. Services prüfen

| Dienst | URL |
|--------|-----|
| Headscale | `https://headscale.homelab-external.robinwerner.net` |
| Headplane | `https://headscale.homelab-external.robinwerner.net/admin` |
| Uptime Kuma | `https://uptime.homelab-external.robinwerner.net` |
| ntfy | `https://ntfy.homelab-external.robinwerner.net` |
| Healthchecks | `https://hc.homelab-external.robinwerner.net` |
| Traefik | `https://traefik.homelab-external.robinwerner.net` |

---

## Phase 2: NUC als Heimnetz-Gateway einrichten

Der NUC im Heimnetz wird per Tailscale mit dem Hetzner Server verbunden.
Er übernimmt zwei Rollen:

- **Subnet Router**: Macht das Heimnetz (10.10.10.0/24) für alle VPN-Clients erreichbar
- **Exit Node**: Leitet den gesamten Internet-Traffic von mobilen Geräten über das Heimnetz (Pi-hole)

### 1. IP-Forwarding aktivieren (auf dem NUC)

```bash
# Temporär (sofort aktiv)
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv6.conf.all.forwarding=1

# Permanent (überlebt Neustart)
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
```

### 2. Docker Compose für Tailscale (auf dem NUC)

Erstelle ein Verzeichnis und die Konfiguration:

```bash
mkdir -p ~/tailscale-gateway && cd ~/tailscale-gateway
```

`docker-compose.yml`:

```yaml
services:
  tailscale:
    image: ghcr.io/tailscale/tailscale:v1.94.2
    container_name: tailscale
    hostname: nuc-homelab
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    volumes:
      - ./tailscale-data:/var/lib/tailscale
      - /dev/net/tun:/dev/net/tun
    environment:
      - TS_STATE_DIR=/var/lib/tailscale
      - TS_EXTRA_ARGS=--login-server=https://headscale.homelab-external.robinwerner.net --advertise-routes=10.10.10.0/24 --advertise-exit-node --accept-dns=false
      - TS_AUTHKEY=${TS_AUTHKEY}
    network_mode: host
```

`.env`:

```bash
# Pre-Auth Key (wird in Schritt 3 erstellt)
TS_AUTHKEY=
```

### 3. Pre-Auth Key erstellen und Container starten

```bash
# Auf dem Hetzner Server: Pre-Auth Key erstellen
ssh -i ~/.ssh/id_ed25519 root@<SERVER_IP> \
  'docker exec headscale headscale preauthkeys create --user homelab --expiration 24h'

# Key in .env eintragen
cd ~/tailscale-gateway
echo "TS_AUTHKEY=<KEY>" > .env

# Container starten
docker compose up -d

# Prüfen ob verbunden
docker exec tailscale tailscale status
```

### 4. Routen und Exit Node in Headscale freigeben

Der NUC hat seine Subnet Route und Exit Node angekündigt, aber Headscale
muss diese noch freigeben:

```bash
# Auf dem Hetzner Server
ssh -i ~/.ssh/id_ed25519 root@<SERVER_IP>

# Alle Routen anzeigen
docker exec headscale headscale routes list

# Subnet Route freigeben (10.10.10.0/24)
docker exec headscale headscale routes enable -r <ROUTE_ID>

# Exit Node freigeben (0.0.0.0/0 und ::/0)
docker exec headscale headscale routes enable -r <EXIT_NODE_ROUTE_ID_V4>
docker exec headscale headscale routes enable -r <EXIT_NODE_ROUTE_ID_V6>
```

`headscale routes list` zeigt alle verfügbaren Routen mit IDs.
Die Subnet Route ist `10.10.10.0/24`, die Exit Node Routen sind `0.0.0.0/0` und `::/0`.

### 5. DNS auf Pi-hole umstellen

Damit mobile Geräte automatisch Pi-hole als DNS nutzen, die Headscale
DNS-Konfiguration anpassen.

In `hetzner/headscale/config.yaml` den DNS-Block ändern:

```yaml
dns:
  magic_dns: true
  base_domain: tailnet

  nameservers:
    global:
      - 10.10.10.X  # <-- Pi-hole IP im Heimnetz

  split: {}
  extra_records: []
```

Danach Headscale neu starten:

```bash
ssh -i ~/.ssh/id_ed25519 root@<SERVER_IP> \
  'cd /opt/homelab-repo/hetzner && docker compose restart headscale'
```

Der Hetzner Server ist davon nicht betroffen — sein Tailscale Client
läuft mit `--accept-dns=false` und nutzt weiterhin seinen eigenen DNS.

> **Hinweis**: Wenn später VLANs hinzukommen, zusätzliche Subnetze in
> `--advertise-routes` aufnehmen (kommasepariert, z.B.
> `--advertise-routes=10.10.10.0/24,10.10.20.0/24`) und in der
> Headscale ACL freigeben.

---

## Phase 3: Endgeräte verbinden

### macOS

```bash
# Tailscale installieren
brew install tailscale

# Pre-Auth Key erstellen (auf dem Hetzner Server)
ssh -i ~/.ssh/id_ed25519 root@<SERVER_IP> \
  'docker exec headscale headscale preauthkeys create --user homelab --expiration 24h'

# Mit Headscale verbinden
tailscale up \
  --login-server=https://headscale.homelab-external.robinwerner.net \
  --authkey=<KEY> \
  --accept-routes

# Exit Node aktivieren (NUC als Gateway)
tailscale set --exit-node=nuc-homelab
```

Oder über die Tailscale GUI: Menüleisten-Icon → **Use Exit Node** → `nuc-homelab`.

Mit aktivem Exit Node läuft dein gesamter Traffic über den NUC im Heimnetz,
inklusive DNS über Pi-hole. Es fühlt sich an als wärst du zuhause.

Exit Node deaktivieren:

```bash
tailscale set --exit-node=
```

### iOS / Android

1. **Tailscale App** installieren (App Store / Play Store)
2. App öffnen → Einstellungen (drei Punkte oben) → **Use an alternate coordination server**
3. URL eingeben: `https://headscale.homelab-external.robinwerner.net`
4. **Sign in** tippen — es öffnet sich eine Headscale-Seite mit einem Node Key
5. Diesen Node auf dem Server registrieren:

```bash
ssh -i ~/.ssh/id_ed25519 root@<SERVER_IP> \
  'docker exec headscale headscale nodes register --user homelab --key mkey:<KEY_VON_DER_SEITE>'
```

6. In der Tailscale App: **Exit Node** → `nuc-homelab` auswählen

Alternativ kannst du statt Schritt 5 auch einen Pre-Auth Key nutzen. Dann
erkennt Headscale das Gerät automatisch, ohne manuelles Registrieren.

---

## Verwaltung

### SSH zum Server

```bash
ssh -i ~/.ssh/id_ed25519 root@<SERVER_IP>
```

### Docker Compose (auf dem Server)

```bash
cd /opt/homelab-repo/hetzner
docker compose ps                                    # Status
docker compose logs -f <service>                     # Logs
docker compose pull && docker compose up -d          # Update
```

### Auto-Update

Der Server prüft jeden Dienstag um 12:00 UTC ob neue Commits auf `main`
vorliegen (z.B. von Renovate). Bei Änderungen wird automatisch
`git pull && docker compose pull && docker compose up -d` ausgeführt.

Log: `/var/log/homelab-update.log`

Manuell auslösen:

```bash
bash /opt/homelab-repo/hetzner/scripts/auto-update.sh
```

### Headscale

```bash
docker exec headscale headscale users list
docker exec headscale headscale nodes list
docker exec headscale headscale preauthkeys create --user homelab --expiration 24h
docker exec headscale headscale routes list
```

---

## Teardown

```bash
./teardown.sh
```

Löscht: Server, Firewall, SSH Key, alle DNS Records.
Fragt vorher "yes" als Bestätigung.

Der NUC-Container im Heimnetz muss separat gestoppt werden:

```bash
cd ~/tailscale-gateway && docker compose down
```

---

## Troubleshooting

### Container starten nicht

```bash
cd /opt/homelab-repo/hetzner
docker compose logs -f
```

### SSL-Zertifikate fehlen

```bash
docker logs traefik
# acme.json muss 600 sein:
chmod 600 /opt/homelab-data/traefik/certs/acme.json
```

### VPN-Verbindung funktioniert nicht

```bash
# Tailscale Status prüfen (auf dem NUC)
docker exec tailscale tailscale status

# Headscale Nodes und Routen prüfen (auf Hetzner)
docker exec headscale headscale nodes list
docker exec headscale headscale routes list

# Alle Routen enabled? Subnet Route und Exit Node müssen "enabled" sein
```

### Heimnetz-Geräte nicht erreichbar (trotz VPN)

```bash
# IP-Forwarding aktiv auf dem NUC?
sysctl net.ipv4.ip_forward
# Muss 1 sein

# Subnet Route in Headscale freigegeben?
docker exec headscale headscale routes list
# 10.10.10.0/24 muss "enabled" sein

# Ping vom Hetzner Server ins Heimnetz
docker exec tailscale tailscale ping 10.10.10.1
```

### Exit Node / Pi-hole funktioniert nicht

```bash
# Exit Node Route freigegeben?
docker exec headscale headscale routes list
# 0.0.0.0/0 und ::/0 müssen "enabled" sein

# DNS-Konfiguration prüfen
tailscale status --json | jq '.Self.DNSServers'
# Sollte die Pi-hole IP zeigen

# Pi-hole direkt testen (vom NUC)
dig @10.10.10.X google.com
```

### Headscale Health Check schlägt fehl

```bash
docker exec headscale headscale health
docker compose logs headscale
```
