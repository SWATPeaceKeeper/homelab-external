# Monitoring & Logging Konzept - Homelab

**Version:** 2.0  
**Stand:** Januar 2026  
**Status:** Konzept zur Umsetzung  
**Abhängigkeit:** VPN_KONZEPT_HEADSCALE_V1.md

---

## Inhaltsverzeichnis

1. [Übersicht & Ziele](#1-übersicht--ziele)
2. [Architektur-Diagramm](#2-architektur-diagramm)
3. [Komponenten-Übersicht](#3-komponenten-übersicht)
4. [Metriken-Stack](#4-metriken-stack)
5. [Log-Aggregation](#5-log-aggregation)
6. [Alerting & Notifications](#6-alerting--notifications)
7. [Container-Update-Monitoring](#7-container-update-monitoring)
8. [Externe Überwachung](#8-externe-überwachung)
9. [Speicher-Planung](#9-speicher-planung)
10. [Implementierungs-Phasen](#10-implementierungs-phasen)
11. [Kostenübersicht](#11-kostenübersicht)

---

## 1. Übersicht & Ziele

### Zielsetzung

| Ziel | Beschreibung |
|------|--------------|
| **Vollständige Observability** | Metriken + Logs für alle ~30 Docker-Container |
| **Long-Term Storage** | Metriken: 5 Jahre, Logs: 1 Jahr |
| **Externe Überwachung** | Unabhängig vom Homelab (erkennt NUC-Ausfall) |
| **Proaktives Alerting** | Push-Benachrichtigungen bei Problemen |
| **Container-Updates** | Benachrichtigungen ohne Auto-Updates |

### Design-Prinzipien

| Prinzip | Umsetzung |
|---------|-----------|
| **Unabhängigkeit** | Externe Komponenten auf Hetzner vServer |
| **Langlebigkeit** | Long-Term Storage auf UNAS Pro (NFS) |
| **Einfachheit** | Bewährte Tools, minimale Komplexität |
| **Sicherheit** | VPN für Zugriff auf interne Dienste (→ siehe VPN-Konzept) |

### Nicht im Scope

- ~~Kubernetes-Cluster~~ (nicht mehr vorhanden)
- ~~Thanos~~ (Overkill für Single-Node Setup)
- ~~Auto-Updates~~ (nur Benachrichtigungen)

### Abhängigkeiten

| Abhängigkeit | Dokument | Beschreibung |
|--------------|----------|--------------|
| **VPN** | `VPN_KONZEPT_HEADSCALE_V1.md` | Headscale für Zugriff Hetzner → Homelab |

---

## 2. Architektur-Diagramm

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        MONITORING & LOGGING ARCHITEKTUR                         │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│   HETZNER vSERVER (extern)                                                     │
│   ════════════════════════                                                     │
│   ┌─────────────────────────────────────────────────────────────┐              │
│   │  Headscale    │  Uptime Kuma  │  ntfy        │  Healthchecks│              │
│   │  (VPN)        │  (Status)     │  (Push)      │  (Cronjobs)  │              │
│   └───────────────┴───────────────┴──────────────┴──────────────┘              │
│          │                │                                                     │
│          │ Tailnet        │ HTTP via Tailnet                                   │
│          ▼                ▼                                                     │
│   ═══════════════════════════════════════════════════════════════════════      │
│                                                                                 │
│   HOMELAB - NUC (intern)                                                       │
│   ══════════════════════                                                       │
│                                                                                 │
│   ┌─────────────────────────────────────────────────────────────────────┐      │
│   │                         METRIKEN                                    │      │
│   │  ┌─────────────┐     remote_write      ┌──────────────────┐        │      │
│   │  │ Prometheus  │ ────────────────────► │ VictoriaMetrics  │        │      │
│   │  │ (7 Tage)    │                       │ (5 Jahre)        │        │      │
│   │  │ NUC SSD     │                       │ UNAS Pro NFS     │        │      │
│   │  └──────┬──────┘                       └────────┬─────────┘        │      │
│   │         │                                       │                  │      │
│   │         │ scrape                                │                  │      │
│   │         ▼                                       │                  │      │
│   │  ┌─────────────────────────┐                   │                  │      │
│   │  │ node-exporter           │                   │                  │      │
│   │  │ cAdvisor                │                   │                  │      │
│   │  │ Traefik Metrics         │                   │                  │      │
│   │  │ UnPoller                │                   │                  │      │
│   │  └─────────────────────────┘                   │                  │      │
│   └────────────────────────────────────────────────┼────────────────────┘      │
│                                                    │                           │
│   ┌─────────────────────────────────────────────────────────────────────┐      │
│   │                           LOGS                                      │      │
│   │  ┌─────────────┐       push logs        ┌──────────────────┐       │      │
│   │  │   Alloy     │ ─────────────────────► │      Loki        │       │      │
│   │  │ (Collector) │                        │   (1 Jahr)       │       │      │
│   │  └──────┬──────┘                        │   UNAS Pro NFS   │       │      │
│   │         │                               └────────┬─────────┘       │      │
│   │         │ collect                                │                 │      │
│   │         ▼                                        │                 │      │
│   │  ┌─────────────────────────┐                    │                 │      │
│   │  │ Docker Logs             │                    │                 │      │
│   │  │ UniFi Syslog            │                    │                 │      │
│   │  │ Traefik Access Logs     │                    │                 │      │
│   │  └─────────────────────────┘                    │                 │      │
│   └─────────────────────────────────────────────────┼───────────────────┘      │
│                                                     │                          │
│   ┌─────────────────────────────────────────────────────────────────────┐      │
│   │                       VISUALISIERUNG                                │      │
│   │                                                                     │      │
│   │                      ┌──────────────┐                              │      │
│   │                      │   Grafana    │◄─── Prometheus (7d)          │      │
│   │                      │              │◄─── VictoriaMetrics (5y)     │      │
│   │                      │              │◄─── Loki (1y)                │      │
│   │                      └──────────────┘                              │      │
│   │                                                                     │      │
│   └─────────────────────────────────────────────────────────────────────┘      │
│                                                                                 │
│   ┌─────────────────────────────────────────────────────────────────────┐      │
│   │                         ALERTING                                    │      │
│   │                                                                     │      │
│   │  Prometheus ──► Alertmanager ──► ntfy (Hetzner) ──► Handy          │      │
│   │                                                                     │      │
│   └─────────────────────────────────────────────────────────────────────┘      │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Komponenten-Übersicht

### Standort: NUC (Homelab)

| Komponente | Funktion | Speicherort | Retention |
|------------|----------|-------------|-----------|
| **Prometheus** | Metriken sammeln, Alerting | NUC SSD | 7 Tage |
| **VictoriaMetrics** | Long-Term Metriken | UNAS Pro (NFS) | 5 Jahre |
| **Loki** | Log-Aggregation | UNAS Pro (NFS) | 1 Jahr |
| **Alloy** | Log-Collector | NUC SSD | - |
| **Grafana** | Dashboards | NUC SSD | - |
| **Alertmanager** | Alert-Routing | NUC SSD | - |
| **MqDockerUp** | Container-Updates | NUC SSD | - |
| **Tailscale** | VPN-Client (Subnet Router) | NUC SSD | - |

### Standort: Hetzner vServer (Extern)

| Komponente | Funktion | Zugriff |
|------------|----------|---------|
| **Headscale** | VPN Coordination | Public |
| **Headplane** | VPN Web-UI | Public (Auth) |
| **Uptime Kuma** | Uptime Monitoring | Via Tailnet ins Homelab |
| **ntfy** | Push-Notifications | Public (Topic-Auth) |
| **Healthchecks** | Cronjob-Monitoring | Public (Ping URLs) |

---

## 4. Metriken-Stack

### 4.1 Warum Prometheus + VictoriaMetrics?

| Anforderung | Prometheus allein | Mit VictoriaMetrics |
|-------------|-------------------|---------------------|
| NFS-Support | ❌ Nicht unterstützt | ✅ Offiziell supported |
| Kompression | ~7 Bytes/Sample | ~1 Byte/Sample (7x besser) |
| 5 Jahre Daten | ❌ Unpraktisch | ✅ ~500 GB auf NFS |
| Alerting | ✅ Nativ | ⚠️ Via Prometheus |
| PromQL | ✅ Nativ | ✅ MetricsQL (kompatibel) |

**Lösung:** Prometheus für kurzfristige Daten + Alerting, VictoriaMetrics für Long-Term Storage.

### 4.2 Datenfluss

```
┌────────────────┐     scrape      ┌────────────────┐
│  Exporters     │ ◄────────────── │   Prometheus   │
│  - node        │                 │   (7 Tage)     │
│  - cadvisor    │                 │   NUC SSD      │
│  - traefik     │                 └───────┬────────┘
│  - unpoller    │                         │
└────────────────┘                         │ remote_write
                                           ▼
                                   ┌────────────────┐
                                   │ VictoriaMetrics│
                                   │   (5 Jahre)    │
                                   │   UNAS Pro NFS │
                                   └────────────────┘
```

### 4.3 Prometheus Konfiguration

```yaml
# prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']

rule_files:
  - /etc/prometheus/rules/*.yml

# Long-Term Storage
remote_write:
  - url: http://victoriametrics:8428/api/v1/write
    queue_config:
      max_samples_per_send: 10000
      batch_send_deadline: 5s
      capacity: 20000

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']

  - job_name: 'traefik'
    static_configs:
      - targets: ['traefik:8080']

  - job_name: 'unpoller'
    static_configs:
      - targets: ['unpoller:9130']
```

### 4.4 VictoriaMetrics Docker Compose

```yaml
services:
  victoriametrics:
    image: victoriametrics/victoria-metrics:latest
    container_name: victoriametrics
    volumes:
      - /mnt/unas/monitoring/victoriametrics:/storage
    command:
      - '-storageDataPath=/storage'
      - '-retentionPeriod=5y'
      - '-httpListenAddr=:8428'
      - '-search.latencyOffset=5s'      # Für NFS-Latenz
      - '-search.maxConcurrentRequests=16'
    ports:
      - "8428:8428"
    restart: unless-stopped
    networks:
      - monitoring
```

### 4.5 Grafana Datasources

```yaml
# grafana/provisioning/datasources/datasources.yml
apiVersion: 1

datasources:
  # Aktuelle Daten (7 Tage) - schneller
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    jsonData:
      timeInterval: "15s"

  # Historische Daten (5 Jahre)
  - name: VictoriaMetrics
    type: prometheus
    access: proxy
    url: http://victoriametrics:8428
    jsonData:
      timeInterval: "15s"
```

---

## 5. Log-Aggregation

### 5.1 Stack: Alloy → Loki

| Komponente | Rolle | Status |
|------------|-------|--------|
| **Alloy** | Log-Collector (Promtail-Nachfolger) | ✅ Modern, aktiv maintained |
| **Loki** | Log-Storage + Query Engine | ✅ NFS-kompatibel |

### 5.2 Loki Konfiguration

```yaml
# loki-config.yaml
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  instance_addr: 127.0.0.1
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

storage_config:
  filesystem:
    directory: /loki/chunks
  tsdb_shipper:
    active_index_directory: /loki/tsdb-index
    cache_location: /loki/tsdb-cache

limits_config:
  retention_period: 8760h  # 1 Jahr (365 Tage)
  ingestion_rate_mb: 10
  ingestion_burst_size_mb: 20
  max_streams_per_user: 10000
  max_line_size: 256kb

compactor:
  working_directory: /loki/compactor
  compaction_interval: 10m
  retention_enabled: true
  retention_delete_delay: 2h
  delete_request_store: filesystem
```

### 5.3 Loki Docker Compose

```yaml
services:
  loki:
    image: grafana/loki:latest
    container_name: loki
    volumes:
      - ./loki-config.yaml:/etc/loki/local-config.yaml:ro
      - /mnt/unas/monitoring/loki:/loki
    command: -config.file=/etc/loki/local-config.yaml
    ports:
      - "3100:3100"
    restart: unless-stopped
    networks:
      - monitoring
```

### 5.4 Alloy Konfiguration (Auszug)

```alloy
// Docker Log Discovery
discovery.docker "containers" {
  host = "unix:///var/run/docker.sock"
}

// Docker Logs sammeln
loki.source.docker "docker_logs" {
  host       = "unix:///var/run/docker.sock"
  targets    = discovery.docker.containers.targets
  forward_to = [loki.process.docker_logs.receiver]
  labels     = {
    job = "docker",
  }
}

// Log Processing
loki.process "docker_logs" {
  forward_to = [loki.write.default.receiver]
  
  stage.docker {}
  
  stage.static_labels {
    values = {
      source = "docker",
    }
  }
}

// An Loki senden
loki.write "default" {
  endpoint {
    url = "http://loki:3100/loki/api/v1/push"
  }
}
```

### 5.5 Retention nach Log-Typ

| Log-Typ | Retention | Grund |
|---------|-----------|-------|
| **Traefik Access** | 30 Tage | Hohes Volumen, kurze Relevanz |
| **Container Logs** | 90 Tage | Standard für Debugging |
| **UniFi/Netzwerk** | 180 Tage | Security-Analyse |
| **System-kritisch** | 1 Jahr | Audit, Compliance |

*Hinweis: Differenzierte Retention via Labels möglich, aber komplex. Initial 1 Jahr für alles.*

---

## 6. Alerting & Notifications

### 6.1 Alert-Fluss

```
Prometheus → Alertmanager → ntfy (Hetzner) → Handy
                  │
                  └────────────────────────► Home Assistant (optional)
```

### 6.2 Alertmanager Konfiguration

```yaml
# alertmanager.yml
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'severity']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: 'ntfy-notifications'
  
  routes:
    - match:
        severity: critical
      receiver: 'ntfy-critical'
      repeat_interval: 1h

receivers:
  - name: 'ntfy-notifications'
    webhook_configs:
      - url: 'https://ntfy.example.de/homelab-alerts'
        send_resolved: true

  - name: 'ntfy-critical'
    webhook_configs:
      - url: 'https://ntfy.example.de/homelab-critical'
        send_resolved: true
```

### 6.3 Beispiel Alert Rules

```yaml
# prometheus/rules/alerts.yml
groups:
  - name: node
    rules:
      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on {{ $labels.instance }}"
          
      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 15
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Disk space low on {{ $labels.instance }}"

  - name: containers
    rules:
      - alert: ContainerDown
        expr: absent(container_last_seen{name=~".+"}) 
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Container {{ $labels.name }} is down"
```

### 6.4 ntfy auf Hetzner

```yaml
# docker-compose.yml (Hetzner)
services:
  ntfy:
    image: binwiederhier/ntfy:latest
    container_name: ntfy
    command:
      - serve
    environment:
      - TZ=Europe/Berlin
      - NTFY_BASE_URL=https://ntfy.example.de
      - NTFY_UPSTREAM_BASE_URL=https://ntfy.sh
      - NTFY_AUTH_DEFAULT_ACCESS=deny-all
      - NTFY_AUTH_FILE=/var/lib/ntfy/user.db
    volumes:
      - ./ntfy/cache:/var/cache/ntfy
      - ./ntfy/data:/var/lib/ntfy
    ports:
      - "8080:80"
    restart: unless-stopped
```

---

## 7. Container-Update-Monitoring

### 7.1 MqDockerUp statt Watchtower

| Aspekt | Watchtower | MqDockerUp |
|--------|------------|------------|
| Status | ⚠️ Archiviert (Dez 2025) | ✅ Aktiv maintained |
| Docker 28/29+ | ❌ Nicht kompatibel | ✅ Kompatibel |
| Home Assistant | ❌ Keine Integration | ✅ MQTT Auto-Discovery |
| Auto-Update | ✅ (unerwünscht) | ✅ Optional |

### 7.2 MqDockerUp Konfiguration

```yaml
# docker-compose.yml
services:
  mqdockerup:
    image: michelkaeser/mqdockerup:latest
    container_name: mqdockerup
    environment:
      - MQTT_CONNECTIONURI=tcp://mosquitto:1883
      - MQTT_TOPIC=homeassistant
      - MQTT_CLIENTID=mqdockerup
      - INTERVAL=3600          # Stündlich prüfen
      - LOGLEVEL=INFO
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    restart: unless-stopped
    networks:
      - default
```

### 7.3 Home Assistant Integration

MqDockerUp erstellt automatisch Entities in Home Assistant:

- `binary_sensor.docker_<container>_update_available`
- `sensor.docker_<container>_current_version`
- `sensor.docker_<container>_latest_version`

**Dashboard-Karte:**
```yaml
type: entities
title: Container Updates
entities:
  - entity: binary_sensor.docker_grafana_update_available
  - entity: binary_sensor.docker_prometheus_update_available
  - entity: binary_sensor.docker_traefik_update_available
```

---

## 8. Externe Überwachung

### 8.1 Uptime Kuma (Hetzner)

**Zugriff auf Homelab via Tailnet (VPN):**

```yaml
# docker-compose.yml (Hetzner)
services:
  uptime-kuma:
    image: louislam/uptime-kuma:latest
    container_name: uptime-kuma
    volumes:
      - ./uptime-kuma:/app/data
    ports:
      - "3001:3001"
    restart: unless-stopped
    # Zugriff auf Tailnet via host network oder eigenen Tailscale Container
    network_mode: host
```

**Zu überwachende Dienste:**

| Dienst | Check-Typ | URL/Target |
|--------|-----------|------------|
| Home Assistant | HTTP | `http://192.168.x.10:8123` |
| Grafana | HTTP | `http://192.168.x.10:3000` |
| Traefik | HTTP | `http://192.168.x.10:8080/ping` |
| PiHole | HTTP | `http://192.168.x.53/admin` |
| NUC SSH | TCP | `192.168.x.10:22` |
| UNAS Pro | Ping | `192.168.x.30` |

### 8.2 Healthchecks (Cronjob-Monitoring)

**Borgmatic Integration:**

```yaml
# borgmatic config
healthchecks:
  ping_url: https://hc.example.de/ping/<uuid>
```

**Weitere Checks:**
- Systemd-Timer für Backups
- Rclone Sync Jobs
- Certbot Renewal

### 8.3 Push-Monitor (Heartbeat)

Zusätzlich zum aktiven Monitoring: NUC meldet sich regelmäßig bei Uptime Kuma:

```bash
# Cronjob auf NUC
*/5 * * * * curl -fsS -m 10 --retry 5 "https://uptime.example.de/api/push/<token>?status=up&msg=OK" > /dev/null
```

---

## 9. Speicher-Planung

### 9.1 Übersicht

```
┌─────────────────────────────────────────────────────────────────────┐
│                      SPEICHER-VERTEILUNG                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   NUC (Lokale SSD)                                                 │
│   ────────────────                                                 │
│   • Prometheus TSDB:     ~5 GB (7 Tage)                            │
│   • Container Volumes:   ~20 GB                                    │
│   • System/Docker:       ~30 GB                                    │
│   ─────────────────────────────────                                │
│   Gesamt:                ~55 GB                                    │
│                                                                     │
│   UNAS Pro (NFS)                                                   │
│   ──────────────                                                   │
│   • VictoriaMetrics:     ~100 GB/Jahr (5 Jahre = ~500 GB)          │
│   • Loki:                ~200 GB/Jahr (1 Jahr = ~200 GB)           │
│   ─────────────────────────────────                                │
│   Gesamt Jahr 1:         ~300 GB                                   │
│   Gesamt Jahr 5:         ~700 GB                                   │
│                                                                     │
│   Hetzner vServer (20 GB SSD)                                      │
│   ───────────────────────────                                      │
│   • System:              ~5 GB                                     │
│   • Uptime Kuma:         ~1 GB                                     │
│   • ntfy Cache:          ~1 GB                                     │
│   • Healthchecks:        ~1 GB                                     │
│   • Headscale:           ~0.5 GB                                   │
│   ─────────────────────────────────                                │
│   Gesamt:                ~8.5 GB (viel Reserve)                    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 9.2 NFS Mount Konfiguration

```bash
# /etc/fstab auf NUC

# UNAS Pro Monitoring Share
192.168.x.30:/monitoring  /mnt/unas/monitoring  nfs4  defaults,_netdev,noatime,nofail  0  0
```

```bash
# Mount-Verzeichnisse erstellen
sudo mkdir -p /mnt/unas/monitoring/{victoriametrics,loki}

# Testen
sudo mount -a
df -h /mnt/unas/monitoring
```

### 9.3 Retention-Übersicht

| Komponente | Speicherort | Retention |
|------------|-------------|-----------|
| Prometheus | NUC SSD | 7 Tage |
| VictoriaMetrics | UNAS Pro | 5 Jahre |
| Loki | UNAS Pro | 1 Jahr |
| Uptime Kuma | Hetzner | 90 Tage |
| Healthchecks | Hetzner | 1 Jahr |

---

## 10. Implementierungs-Phasen

### Voraussetzung: VPN

**→ Siehe `VPN_KONZEPT_HEADSCALE_V1.md`**

Das VPN muss zuerst eingerichtet werden, damit der Hetzner vServer das Homelab erreichen kann.

### Phase 1: Lokaler Metriken-Stack (2-3 Stunden)

```
[ ] NFS-Mount für UNAS Pro einrichten
    sudo mkdir -p /mnt/unas/monitoring/{victoriametrics,loki}
    
[ ] VictoriaMetrics deployen
    - Storage auf /mnt/unas/monitoring/victoriametrics
    - Retention: 5 Jahre
    
[ ] Prometheus aktualisieren
    - remote_write zu VictoriaMetrics
    - Retention auf 7 Tage reduzieren
    
[ ] Grafana Datasources konfigurieren
    - Prometheus (default, 7d)
    - VictoriaMetrics (historisch, 5y)
```

### Phase 2: Log-Aggregation (2-3 Stunden)

```
[ ] Loki deployen
    - Storage auf /mnt/unas/monitoring/loki
    - Retention: 1 Jahr
    - Config mit TSDB v13
    
[ ] Alloy konfigurieren
    - Docker Log Discovery
    - UniFi Syslog (bereits vorhanden)
    - Traefik Access Logs
    
[ ] Grafana Datasource hinzufügen
    - Loki
    
[ ] Test: Logs in Grafana sichtbar?
```

### Phase 3: Alerting (1-2 Stunden)

```
[ ] Alertmanager konfigurieren
    - Route zu ntfy
    
[ ] Alert Rules erstellen
    - CPU, RAM, Disk
    - Container Down
    - Backup-Fehler
    
[ ] ntfy auf Hetzner deployen
    
[ ] Test: Alert auslösen → Push kommt an?
```

### Phase 4: Externe Überwachung (1-2 Stunden)

```
[ ] Uptime Kuma auf Hetzner deployen

[ ] Tailscale auf Hetzner installieren
    - Mit Headscale verbinden
    
[ ] Monitoring-Checks anlegen
    - Home Assistant, Grafana, PiHole, etc.
    - Via Tailnet-IPs (192.168.x.x)
    
[ ] Push-Monitor (Heartbeat) einrichten
    
[ ] Status-Page konfigurieren (optional)
```

### Phase 5: Container-Update-Monitoring (30 Minuten)

```
[ ] MqDockerUp deployen
    - MQTT-Verbindung zu Mosquitto
    
[ ] Home Assistant prüfen
    - Entities erscheinen automatisch
    
[ ] Dashboard-Karte erstellen
```

### Phase 6: Healthchecks Migration (1 Stunde)

```
[ ] Healthchecks.io self-hosted deployen (Hetzner)

[ ] Borgmatic umkonfigurieren
    - Neue Ping-URL
    
[ ] Weitere Cronjobs einbinden

[ ] Alte Healthchecks.io deaktivieren
```

---

## 11. Kostenübersicht

### Laufende Kosten

| Posten | Kosten/Monat | Anmerkung |
|--------|--------------|-----------|
| Hetzner vServer (CX11) | ~4,50€ | 2 vCPU, 4 GB RAM, 40 GB SSD |
| Domain (optional) | ~1€ | Falls nicht vorhanden |
| **Gesamt** | **~5,50€/Monat** | |

### Einmalige Kosten

| Posten | Kosten | Anmerkung |
|--------|--------|-----------|
| UNAS Pro Speicher | 0€ | Bereits vorhanden |
| Zeit | ~10-15h | Einrichtung |

### Ersparnis vs. SaaS

| SaaS-Alternative | Kosten/Monat |
|------------------|--------------|
| Datadog | ~30€+ |
| New Relic | ~25€+ |
| Healthchecks.io Pro | ~5€ |
| UptimeRobot Pro | ~7€ |
| **Gesamt SaaS** | **~70€+/Monat** |

**Ersparnis: ~65€/Monat = ~780€/Jahr**

---

## Anhang A: Wichtige URLs

| Dienst | URL | Standort |
|--------|-----|----------|
| Grafana | http://192.168.x.10:3000 | NUC |
| Prometheus | http://192.168.x.10:9090 | NUC |
| VictoriaMetrics | http://192.168.x.10:8428 | NUC |
| Alertmanager | http://192.168.x.10:9093 | NUC |
| Loki | http://192.168.x.10:3100 | NUC |
| Uptime Kuma | https://uptime.example.de | Hetzner |
| ntfy | https://ntfy.example.de | Hetzner |
| Healthchecks | https://hc.example.de | Hetzner |

---

## Anhang B: Checkliste für Go-Live

```
VORAUSSETZUNGEN
───────────────
[ ] VPN-Tunnel stabil (→ VPN-Konzept)
[ ] NFS-Mounts persistent

METRIKEN
────────
[ ] Prometheus scraping alle Targets
[ ] VictoriaMetrics empfängt remote_write
[ ] Grafana zeigt beide Datasources

LOGS
────
[ ] Alloy sammelt Docker Logs
[ ] Loki empfängt und speichert
[ ] Grafana Explore zeigt Logs

ALERTING
────────
[ ] Alertmanager → ntfy funktioniert
[ ] Test-Alert ausgelöst und empfangen

EXTERNE ÜBERWACHUNG
───────────────────
[ ] Uptime Kuma erreicht alle internen Dienste
[ ] Healthchecks empfängt Borgmatic Pings
[ ] Push-Monitor aktiv

POST-LAUNCH
───────────
[ ] 1 Woche ohne manuelle Eingriffe
[ ] Alle Alerts getestet
[ ] Dokumentation vollständig
```

---

## Anhang C: Entscheidungs-Log

| Entscheidung | Gewählt | Alternative | Grund |
|--------------|---------|-------------|-------|
| Long-Term Metriken | VictoriaMetrics | Thanos | Einfacher, NFS-Support, 1 Binary |
| Container-Updates | MqDockerUp | Watchtower | Watchtower deprecated, HA-Integration |
| Log-Collector | Alloy | Promtail | Promtail deprecated |
| VPN | Headscale | Plain WireGuard | NAT Traversal, Mobile Clients, MagicDNS |
| Notifications | ntfy (self-hosted) | Pushover | Open Source, modern |
| Metriken-Storage | UNAS Pro (NFS) | NUC SSD | Mehr Platz, Jahre Retention |

---

*Dokument erstellt: Januar 2026*  
*Abhängigkeit: VPN_KONZEPT_HEADSCALE_V1.md*  
*Nächste Review: Nach Phase 6*
