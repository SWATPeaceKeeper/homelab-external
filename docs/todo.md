# TODO - Zukünftige Ideen

## VPN / Headscale

- [ ] **Per-User ACL-Einschränkungen**: Zusätzliche User (z.B. `partner`, `gast`) mit eingeschränktem Zugriff anlegen. Beispiel: Gäste nur auf bestimmte Services, Partner auf alles außer IoT-Geräte.
- [ ] **VLAN-Segmentierung**: Heimnetz in VLANs aufteilen (z.B. `10.10.10.0/24` Mgmt, `10.10.20.0/24` IoT, `10.10.30.0/24` Gäste). Zusätzliche Subnetze in `--advertise-routes` und ACL aufnehmen.
- [ ] **IPv6-Support**: Aktuell nur IPv4 A-Records. AAAA-Records bei Cloudflare anlegen und Headscale IPv6-Prefix (`fd7a:115c:a1e0::/48`) nutzen.

## Monitoring & Alerting

- [ ] **Weitere Heimnetz-Ports in ACL**: Bei Bedarf zusätzliche Ports für `tag:server` freigeben (aktuell: 53, 80, 443, 3000, 8080, 8123, 9090, 9100).
- [ ] **ntfy-Integration**: Uptime Kuma und Healthchecks mit ntfy verbinden, damit Alerts als Push-Notification aufs Handy kommen.
- [ ] **Monitoring-Integration-Guide**: Dokumentieren welche Uptime Kuma Monitors für Heimnetz-Services eingerichtet werden sollen (HTTP, TCP, Ping).

## Infrastruktur

- [ ] **Backup-Strategie**: Persistente Daten unter `/opt/homelab-data/` regelmäßig sichern (Headscale DB, Uptime Kuma, Healthchecks). Restic oder Borg als Tool evaluieren.
- [ ] **Container Resource Limits**: Memory/CPU-Limits (`deploy.resources`) für alle Container setzen, damit ein einzelner Service nicht den ganzen Server lahmlegt.
- [ ] **Log-Rotation**: `/var/log/homelab-update.log` und Traefik Access Logs (`/var/log/traefik/`) wachsen unbegrenzt. Logrotate-Config in `cloud-init.yaml` einrichten.
- [ ] **Traefik E-Mail parametrisieren**: ACME-E-Mail ist in `traefik/traefik.yml` hardcoded (`kontakt@robinwerner.de`). In `.env` auslagern für Wiederverwendbarkeit.

## Operational

- [ ] **Post-Bootstrap Health Check**: Script das nach `bootstrap.sh` automatisch alle Service-Endpoints prüft (HTTPS erreichbar, Healthchecks grün).
- [ ] **Disaster Recovery Playbook**: Dokumentieren was bei DB-Korruption, vollem Disk, abgelaufenem Tailscale Key etc. zu tun ist.
- [ ] **GitHub Actions Linting**: Workflow für `shellcheck` (Shell Scripts) und `docker compose config` (Compose Validierung) bei PRs.
