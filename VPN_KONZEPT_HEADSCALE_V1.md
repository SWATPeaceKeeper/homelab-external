# VPN-Konzept - Headscale Mesh-Netzwerk

**Version:** 1.0  
**Stand:** Januar 2026  
**Status:** Konzept zur Umsetzung

---

## Inhaltsverzeichnis

1. [Übersicht & Ziele](#1-übersicht--ziele)
2. [Technologie-Vergleich](#2-technologie-vergleich)
3. [Architektur](#3-architektur)
4. [Komponenten](#4-komponenten)
5. [Netzwerk-Design](#5-netzwerk-design)
6. [Installation Headscale Server](#6-installation-headscale-server)
7. [Installation Headplane UI](#7-installation-headplane-ui)
8. [Client-Konfiguration](#8-client-konfiguration)
9. [Subnet Router (LAN-Zugriff)](#9-subnet-router-lan-zugriff)
10. [Exit Node (Internet über Homelab)](#10-exit-node-internet-über-homelab)
11. [ACL-Konfiguration](#11-acl-konfiguration)
12. [DNS-Integration](#12-dns-integration)
13. [Anwendungsfälle](#13-anwendungsfälle)
14. [Implementierungs-Phasen](#14-implementierungs-phasen)
15. [Wartung & Troubleshooting](#15-wartung--troubleshooting)

---

## 1. Übersicht & Ziele

### Was ist Headscale?

**Headscale** ist ein selbst-gehosteter, Open-Source Coordination Server für Tailscale. Tailscale selbst baut auf WireGuard auf und bietet ein **Mesh-VPN** mit automatischem NAT-Traversal, Key-Management und einer exzellenten User Experience.

Mit Headscale behältst du die volle Kontrolle über deine Daten – kein externer Coordination Server bei Tailscale Inc. nötig.

### Zielsetzung

| Ziel | Beschreibung |
|------|--------------|
| **Homelab-Zugriff** | Von überall sicher auf interne Dienste zugreifen |
| **Monitoring-Anbindung** | Hetzner vServer kann interne Dienste überwachen |
| **Mobile Geräte** | Handy/Tablet ins Tailnet einbinden |
| **Einfachheit** | Kein manuelles Key-Management, automatisches NAT-Traversal |
| **Erweiterbarkeit** | Weitere Geräte/Standorte einfach hinzufügen |

### Design-Prinzipien

| Prinzip | Umsetzung |
|---------|-----------|
| **Self-Hosted** | Headscale auf eigenem Hetzner vServer |
| **Zero Trust** | ACLs für granulare Zugriffskontrolle |
| **Automatisierung** | MagicDNS, automatische Key-Rotation |
| **Ausfallsicherheit** | Mesh-Verbindungen bleiben auch bei Coordination-Server-Ausfall |

---

## 2. Technologie-Vergleich

### Plain WireGuard vs. Headscale/Tailscale

| Feature | Plain WireGuard | Headscale/Tailscale |
|---------|-----------------|---------------------|
| **Basis** | WireGuard | WireGuard |
| **Setup** | Manuell (Keys, IPs, Config) | Automatisch |
| **NAT Traversal** | Port-Forward nötig | Automatisch (STUN, DERP) |
| **Key Rotation** | Manuell | Automatisch |
| **Mesh-Netzwerk** | Manuell konfigurieren | Automatisch |
| **DNS** | Manuell | MagicDNS (node.tailnet) |
| **ACLs** | iptables | JSON-basiert, granular |
| **Client-Support** | Config-Dateien | Native Apps (alle Plattformen) |
| **Web-UI** | Keins | Headplane |
| **Komplexität** | Niedrig (für 2 Nodes) | Höher initial, skaliert besser |

### Wann Headscale wählen?

✅ **Headscale ist ideal wenn:**
- Mehr als 2 Nodes verbunden werden sollen
- Mobile Geräte (iOS/Android) eingebunden werden
- Kein Port-Forward möglich/gewünscht
- Automatisches Key-Management gewünscht
- MagicDNS und ACLs genutzt werden sollen

❌ **Plain WireGuard reicht wenn:**
- Nur 2 Nodes (Site-to-Site)
- Port-Forward kein Problem
- Maximale Einfachheit gewünscht

---

## 3. Architektur

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        HEADSCALE MESH-NETZWERK                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                         HETZNER vSERVER                                     │
│                    ┌─────────────────────────┐                              │
│                    │      Headscale          │                              │
│                    │   (Coordination Server) │                              │
│                    │                         │                              │
│                    │   + Headplane (Web-UI)  │                              │
│                    │   + Uptime Kuma         │                              │
│                    │   + ntfy                │                              │
│                    │   + Healthchecks        │                              │
│                    └───────────┬─────────────┘                              │
│                                │                                            │
│              Coordination      │      Coordination                          │
│              (HTTPS)           │      (HTTPS)                               │
│                                │                                            │
│         ┌──────────────────────┼──────────────────────┐                     │
│         │                      │                      │                     │
│         ▼                      ▼                      ▼                     │
│   ┌───────────┐          ┌───────────┐          ┌───────────┐              │
│   │   NUC     │◄────────►│  Handy    │◄────────►│  Laptop   │              │
│   │ Tailscale │  WireGuard│ Tailscale │ WireGuard│ Tailscale │              │
│   │  Client   │  (direkt) │  Client   │ (direkt) │  Client   │              │
│   │           │          │           │          │           │              │
│   │ Subnet    │          │           │          │           │              │
│   │ Router    │          │           │          │           │              │
│   └─────┬─────┘          └───────────┘          └───────────┘              │
│         │                                                                   │
│         │ routet                                                            │
│         ▼                                                                   │
│   ┌─────────────────────────────────────┐                                   │
│   │         HOMELAB LAN                 │                                   │
│   │       192.168.x.0/24                │                                   │
│   │                                     │                                   │
│   │  • Home Assistant                   │                                   │
│   │  • Grafana                          │                                   │
│   │  • PiHole                           │                                   │
│   │  • UNAS Pro                         │                                   │
│   │  • Alle internen Dienste            │                                   │
│   └─────────────────────────────────────┘                                   │
│                                                                             │
│   LEGENDE:                                                                  │
│   ─────────────────────────────────────                                     │
│   ──────►  Coordination (Headscale Server, nur Metadaten)                   │
│   ◄──────► WireGuard Tunnel (direkt zwischen Nodes, verschlüsselt)          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Wichtiges Konzept: Coordination vs. Datenfluss

| Typ | Pfad | Inhalt |
|-----|------|--------|
| **Coordination** | Client → Headscale Server | Keys, Node-Info, ACLs, DNS |
| **Datenverkehr** | Client ↔ Client (direkt) | Eigentliche Daten (WireGuard) |

Der Headscale-Server sieht **niemals** den eigentlichen Traffic. Er koordiniert nur, welche Nodes existieren und wie sie sich verbinden können.

---

## 4. Komponenten

### 4.1 Headscale (Coordination Server)

| Eigenschaft | Wert |
|-------------|------|
| **Image** | `headscale/headscale:latest` |
| **Port** | 443 (HTTPS) |
| **Speicher** | SQLite (klein) oder PostgreSQL |
| **Standort** | Hetzner vServer |

### 4.2 Headplane (Web-UI)

| Eigenschaft | Wert |
|-------------|------|
| **Image** | `ghcr.io/tale/headplane:latest` |
| **Port** | 3000 (hinter Reverse Proxy) |
| **Funktion** | Node-Management, User-Management, ACL-Editor |

### 4.3 Tailscale Clients

| Plattform | Installation |
|-----------|--------------|
| **Linux (NUC)** | Docker Container oder native |
| **iOS** | App Store |
| **Android** | Play Store / F-Droid |
| **macOS** | App Store oder brew |
| **Windows** | MSI Installer |

---

## 5. Netzwerk-Design

### IP-Bereiche

| Bereich | CIDR | Verwendung |
|---------|------|------------|
| **Tailnet** | 100.64.0.0/10 | Automatisch von Tailscale vergeben |
| **Homelab LAN** | 192.168.x.0/24 | Bestehendes Netzwerk (via Subnet Router) |

### Geplante Nodes

| Node | Tailnet-IP | Rolle | Funktion |
|------|------------|-------|----------|
| **Hetzner vServer** | 100.64.0.1 | Server + Client | Headscale + Monitoring |
| **NUC** | 100.64.0.2 | Subnet Router | Routet 192.168.x.0/24 |
| **Handy (Robin)** | 100.64.0.3 | Client | Mobiler Zugriff |
| **Laptop** | 100.64.0.4 | Client | Mobiler Zugriff |

### MagicDNS

Nach Setup erreichbar über:
- `nuc.tailnet` → 100.64.0.2
- `hetzner.tailnet` → 100.64.0.1
- Oder: `nuc` (wenn DNS-Suffix konfiguriert)

---

## 6. Installation Headscale Server

### 6.1 Docker Compose (Hetzner vServer)

```yaml
# docker-compose.yml
services:
  headscale:
    image: headscale/headscale:latest
    container_name: headscale
    restart: unless-stopped
    volumes:
      - ./headscale/config:/etc/headscale
      - ./headscale/data:/var/lib/headscale
    ports:
      - "8080:8080"      # HTTP (für Reverse Proxy)
      - "9090:9090"      # Metrics
    command: serve
    environment:
      - TZ=Europe/Berlin

  # Reverse Proxy für HTTPS
  traefik:
    # ... deine bestehende Traefik-Config
    # headscale.example.de → headscale:8080
```

### 6.2 Headscale Konfiguration

```yaml
# headscale/config/config.yaml
---
server_url: https://headscale.example.de
listen_addr: 0.0.0.0:8080
metrics_listen_addr: 0.0.0.0:9090

# Datenbank
database:
  type: sqlite
  sqlite:
    path: /var/lib/headscale/db.sqlite

# DERP (Relay Server für NAT Traversal)
derp:
  server:
    enabled: true
    region_id: 999
    region_code: "home"
    region_name: "Homelab"
    stun_listen_addr: "0.0.0.0:3478"
  urls:
    - https://controlplane.tailscale.com/derpmap/default
  auto_update_enabled: true
  update_frequency: 24h

# IP-Bereich für Clients
prefixes:
  v4: 100.64.0.0/10
  v6: fd7a:115c:a1e0::/48

# DNS
dns:
  magic_dns: true
  base_domain: tailnet
  nameservers:
    global:
      - 192.168.x.53   # PiHole (via Subnet Router erreichbar)
    split: {}

# Logging
log:
  format: text
  level: info

# Node-Einstellungen
ephemeral_node_inactivity_timeout: 30m

# API für Headplane
policy:
  mode: file
  path: /etc/headscale/acl.json
```

### 6.3 Namespace/User erstellen

```bash
# In den Container
docker exec -it headscale headscale namespaces create homelab

# API-Key für Headplane erstellen
docker exec -it headscale headscale apikeys create --expiration 365d
# → Key notieren!
```

---

## 7. Installation Headplane UI

### 7.1 Docker Compose

```yaml
# Ergänzung zu docker-compose.yml
services:
  headplane:
    image: ghcr.io/tale/headplane:latest
    container_name: headplane
    restart: unless-stopped
    environment:
      - HEADSCALE_URL=http://headscale:8080
      - API_KEY=<dein-api-key>
      - COOKIE_SECRET=<random-32-char-string>
      - ROOT_API_KEY=<dein-api-key>
      - DISABLE_API_KEY_LOGIN=false
      - HOST=0.0.0.0
      - PORT=3000
    ports:
      - "3000:3000"
    depends_on:
      - headscale
```

### 7.2 Traefik Labels (HTTPS)

```yaml
services:
  headplane:
    # ...
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.headplane.rule=Host(`vpn.example.de`)"
      - "traefik.http.routers.headplane.tls=true"
      - "traefik.http.routers.headplane.tls.certresolver=letsencrypt"
      - "traefik.http.services.headplane.loadbalancer.server.port=3000"
```

### 7.3 Headplane Features

- ✅ Node-Übersicht (online/offline Status)
- ✅ User/Namespace-Management
- ✅ ACL-Editor (visuell)
- ✅ Pre-Auth Keys generieren
- ✅ Node-Einstellungen (Subnet Routes, Exit Node)
- ✅ DNS-Einstellungen

---

## 8. Client-Konfiguration

### 8.1 NUC (Docker Container)

```yaml
# docker-compose.yml auf NUC
services:
  tailscale:
    image: tailscale/tailscale:latest
    container_name: tailscale
    hostname: nuc
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    volumes:
      - ./tailscale/data:/var/lib/tailscale
      - /dev/net/tun:/dev/net/tun
    environment:
      - TS_AUTHKEY=<preauth-key-von-headplane>
      - TS_STATE_DIR=/var/lib/tailscale
      - TS_EXTRA_ARGS=--login-server=https://headscale.example.de --advertise-routes=192.168.x.0/24 --accept-dns=false
    network_mode: host   # Wichtig für Subnet Routing!
```

**Wichtig:** `network_mode: host` ist erforderlich, damit der Container das Host-Netzwerk routen kann!

### 8.2 NUC (Native Installation - Alternative)

```bash
# Tailscale installieren
curl -fsSL https://tailscale.com/install.sh | sh

# Mit Headscale verbinden
sudo tailscale up \
  --login-server=https://headscale.example.de \
  --authkey=<preauth-key> \
  --advertise-routes=192.168.x.0/24 \
  --accept-dns=false
```

### 8.3 Mobile Geräte (iOS/Android)

1. **Tailscale App** installieren
2. Einstellungen → "Use custom control server"
3. URL eingeben: `https://headscale.example.de`
4. Pre-Auth Key von Headplane verwenden
5. Fertig!

### 8.4 Pre-Auth Keys generieren

```bash
# Via CLI
docker exec -it headscale headscale preauthkeys create \
  --namespace homelab \
  --expiration 24h \
  --reusable

# Oder via Headplane UI (empfohlen)
```

---

## 9. Subnet Router (LAN-Zugriff)

### Konzept

Der **NUC** fungiert als **Subnet Router** und macht das gesamte Homelab-LAN (192.168.x.0/24) für alle Tailnet-Clients erreichbar.

```
┌─────────────────────────────────────────────────────────────────┐
│                    SUBNET ROUTING                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   Handy (100.64.0.3)                                           │
│        │                                                        │
│        │ will erreichen: 192.168.x.10 (Home Assistant)         │
│        │                                                        │
│        ▼                                                        │
│   ┌─────────────────┐                                          │
│   │ NUC (Tailscale) │  "Ich route 192.168.x.0/24"              │
│   │ 100.64.0.2      │                                          │
│   └────────┬────────┘                                          │
│            │                                                    │
│            │ forwards to                                        │
│            ▼                                                    │
│   ┌─────────────────┐                                          │
│   │  Home Assistant │                                          │
│   │  192.168.x.10   │                                          │
│   └─────────────────┘                                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Konfiguration auf NUC

```bash
# Route ankündigen
tailscale up --advertise-routes=192.168.x.0/24

# IP-Forwarding aktivieren (falls nicht schon)
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### Route freigeben (Headscale)

```bash
# Route muss explizit freigegeben werden
docker exec -it headscale headscale routes enable -r <route-id>

# Oder via Headplane UI (einfacher)
```

---

## 10. Exit Node (Internet über Homelab)

### Konzept

Als **Exit Node** leitet der NUC den gesamten Internet-Traffic eines Clients über das Homelab. Nützlich für:
- Öffentliche WLANs (Sicherheit)
- Geo-Blocking umgehen
- Heimnetz-IP nutzen

### Aktivierung auf NUC

```bash
tailscale up --advertise-exit-node
```

### Freigabe in Headscale

```bash
docker exec -it headscale headscale routes enable -r <route-id>
```

### Nutzung auf Client

```bash
# Linux/macOS
tailscale up --exit-node=nuc

# Oder in der App: Exit Node auswählen
```

---

## 11. ACL-Konfiguration

### Grundkonzept

ACLs (Access Control Lists) definieren, welcher Node welche anderen Nodes/Dienste erreichen darf.

### Beispiel-ACL

```json
// headscale/config/acl.json
{
  "groups": {
    "group:admin": ["robin"],
    "group:monitoring": ["hetzner-vserver"]
  },
  
  "hosts": {
    "homelab": "192.168.x.0/24",
    "nuc": "100.64.0.2"
  },
  
  "acls": [
    // Admins dürfen alles
    {
      "action": "accept",
      "src": ["group:admin"],
      "dst": ["*:*"]
    },
    
    // Monitoring-Server darf interne Dienste prüfen
    {
      "action": "accept",
      "src": ["group:monitoring"],
      "dst": [
        "homelab:80",
        "homelab:443",
        "homelab:3000",   // Grafana
        "homelab:8123",   // Home Assistant
        "homelab:9090",   // Prometheus
        "homelab:53"      // PiHole DNS
      ]
    },
    
    // Alle Tailnet-Clients können NUC SSH erreichen
    {
      "action": "accept",
      "src": ["*"],
      "dst": ["nuc:22"]
    }
  ],
  
  "ssh": [
    {
      "action": "accept",
      "src": ["group:admin"],
      "dst": ["*"],
      "users": ["autogroup:nonroot", "root"]
    }
  ]
}
```

### ACL neu laden

```bash
docker exec -it headscale headscale policy reload
```

---

## 12. DNS-Integration

### Option A: PiHole als DNS für Tailnet

Alle Tailnet-Clients nutzen PiHole für DNS (inkl. Ad-Blocking):

```yaml
# In headscale config.yaml
dns:
  magic_dns: true
  base_domain: tailnet
  nameservers:
    global:
      - 192.168.x.53   # PiHole IP (via Subnet Router)
```

### Option B: Split DNS

Nur interne Domains über PiHole, Rest über öffentliche DNS:

```yaml
dns:
  magic_dns: true
  base_domain: tailnet
  nameservers:
    global:
      - 1.1.1.1
      - 8.8.8.8
    split:
      homelab.local:
        - 192.168.x.53
```

### MagicDNS-Namen

Nach Konfiguration sind alle Nodes erreichbar über:
- `nuc.tailnet` → 100.64.0.2
- `handy.tailnet` → 100.64.0.3
- etc.

---

## 13. Anwendungsfälle

### 13.1 Monitoring (Hetzner → Homelab)

```
Uptime Kuma (Hetzner)
        │
        │ HTTPS via Tailnet
        ▼
┌─────────────────┐
│ Interne Dienste │
│ 192.168.x.0/24  │
└─────────────────┘

Checks:
- http://192.168.x.10:8123  → Home Assistant
- http://192.168.x.10:3000  → Grafana
- tcp://192.168.x.10:22     → NUC SSH
```

### 13.2 Mobiler Zugriff (Handy → Homelab)

```
Unterwegs im Café
       │
       │ Tailscale App aktiv
       ▼
┌─────────────────┐
│ Home Assistant  │  → Lichter schalten
│ Grafana         │  → Dashboards checken
│ SSH             │  → Notfall-Zugriff
└─────────────────┘
```

### 13.3 Sicheres Surfen (Exit Node)

```
Öffentliches WLAN
       │
       │ Exit Node: NUC
       ▼
┌─────────────────┐
│    Internet     │  → Gesamter Traffic über Homelab
│    (via NUC)    │  → Heim-IP für Geo-Blocking
└─────────────────┘
```

### 13.4 Remote-Arbeit (Laptop → Homelab)

```
Laptop im Hotel
       │
       │ Tailscale aktiv
       ▼
┌─────────────────┐
│ Entwicklung     │  → Zugriff auf interne APIs
│ Datenbanken     │  → PostgreSQL, Redis
│ Dateiserver     │  → UNAS Pro SMB/NFS
└─────────────────┘
```

---

## 14. Implementierungs-Phasen

### Phase 1: Headscale Server (1-2 Stunden)

```
[ ] Hetzner vServer vorbereiten
[ ] Docker + Traefik installiert
[ ] Headscale Container deployen
[ ] SSL-Zertifikat (Let's Encrypt)
[ ] Namespace "homelab" erstellen
[ ] API-Key generieren
```

### Phase 2: Headplane UI (30 Minuten)

```
[ ] Headplane Container deployen
[ ] Traefik Route konfigurieren
[ ] Login testen
```

### Phase 3: NUC als Subnet Router (1 Stunde)

```
[ ] Tailscale auf NUC installieren (Docker oder native)
[ ] Mit Headscale verbinden
[ ] Subnet Route ankündigen (192.168.x.0/24)
[ ] Route in Headscale freigeben
[ ] IP-Forwarding aktivieren
[ ] Test: Von Hetzner aus 192.168.x.x erreichbar?
```

### Phase 4: Mobile Clients (30 Minuten)

```
[ ] Tailscale App installieren (iOS/Android)
[ ] Custom Control Server konfigurieren
[ ] Pre-Auth Key verwenden
[ ] Test: Homelab erreichbar?
```

### Phase 5: DNS & ACLs (1 Stunde)

```
[ ] PiHole als DNS konfigurieren
[ ] MagicDNS testen
[ ] ACL-Policy erstellen
[ ] Monitoring-Zugriffe freigeben
```

### Phase 6: Exit Node (Optional, 30 Minuten)

```
[ ] Exit Node auf NUC aktivieren
[ ] In Headscale freigeben
[ ] Test: Internet über NUC routen
```

---

## 15. Wartung & Troubleshooting

### Status prüfen

```bash
# Auf Client
tailscale status

# Auf Headscale Server
docker exec -it headscale headscale nodes list
docker exec -it headscale headscale routes list
```

### Logs

```bash
# Headscale
docker logs headscale -f

# Tailscale Client
journalctl -u tailscaled -f
# oder
docker logs tailscale -f
```

### Häufige Probleme

| Problem | Lösung |
|---------|--------|
| Client verbindet nicht | Pre-Auth Key abgelaufen? Neuen erstellen |
| Subnet nicht erreichbar | Route in Headscale freigegeben? IP-Forwarding aktiv? |
| DNS funktioniert nicht | PiHole via Subnet Router erreichbar? |
| Langsame Verbindung | DERP-Relay statt direkter Verbindung? NAT-Typ prüfen |

### Node entfernen

```bash
docker exec -it headscale headscale nodes delete -i <node-id>
```

### Key rotieren

```bash
# Auf Client
tailscale up --force-reauth
```

---

## Anhang A: Wichtige URLs

| Dienst | URL | Beschreibung |
|--------|-----|--------------|
| Headscale | https://headscale.example.de | Coordination Server |
| Headplane | https://vpn.example.de | Web-UI |

---

## Anhang B: Checkliste für Go-Live

```
INFRASTRUKTUR
─────────────
[ ] Headscale läuft mit SSL
[ ] Headplane erreichbar
[ ] DNS-Record für headscale.example.de

CLIENTS
───────
[ ] NUC verbunden und Subnet Router aktiv
[ ] Hetzner vServer verbunden
[ ] Mindestens ein mobiler Client getestet

NETZWERK
────────
[ ] Subnet Route 192.168.x.0/24 freigegeben
[ ] IP-Forwarding auf NUC aktiv
[ ] PiHole als DNS funktioniert

SICHERHEIT
──────────
[ ] ACLs konfiguriert
[ ] Nur notwendige Ports freigegeben
[ ] Pre-Auth Keys mit Ablaufdatum
```

---

## Anhang C: Ressourcen

| Ressource | URL |
|-----------|-----|
| Headscale Docs | https://headscale.net/stable/ |
| Headscale GitHub | https://github.com/juanfont/headscale |
| Headplane GitHub | https://github.com/tale/headplane |
| Tailscale Docs | https://tailscale.com/kb |
| Tailscale ACL Docs | https://tailscale.com/kb/1018/acls |

---

## Anhang D: Erweiterungsmöglichkeiten

### Zukünftige Nodes

| Node | Beschreibung | Priorität |
|------|--------------|-----------|
| Zweiter Standort | Eltern/Freunde anbinden | Niedrig |
| NAS-Backup | Offsite-Backup via Tailnet | Mittel |
| Weitere Handys | Familie einbinden | Mittel |

### Tailscale SSH

Direkter SSH-Zugriff über Tailscale ohne separate SSH-Keys:

```bash
# Aktivieren
tailscale up --ssh

# Verbinden (von anderem Tailnet-Client)
ssh user@nuc
```

### Taildrop (Dateiübertragung)

```bash
# Datei senden
tailscale file cp datei.txt nuc:

# Empfangen (auf NUC)
tailscale file get ~/Downloads/
```

---

*Dokument erstellt: Januar 2026*  
*Nächste Review: Nach Implementierung Phase 3*
