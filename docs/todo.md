# TODO - Zukünftige Ideen

## VPN / Headscale

- [ ] **Per-User ACL-Einschränkungen**: Zusätzliche User (z.B. `partner`, `gast`) mit eingeschränktem Zugriff anlegen. Beispiel: Gäste nur auf bestimmte Services, Partner auf alles außer IoT-Geräte.
- [ ] **VLAN-Segmentierung**: Heimnetz in VLANs aufteilen (z.B. `10.10.10.0/24` Mgmt, `10.10.20.0/24` IoT, `10.10.30.0/24` Gäste). Zusätzliche Subnetze in `--advertise-routes` und ACL aufnehmen.

## Monitoring

- [ ] **Weitere Heimnetz-Ports in ACL**: Bei Bedarf zusätzliche Ports für `tag:server` freigeben (aktuell: 53, 80, 443, 3000, 8080, 8123, 9090, 9100).

## Infrastruktur

- [ ] **Backup-Strategie**: Persistente Daten unter `/opt/homelab-data/` regelmäßig sichern (Headscale DB, Uptime Kuma, Healthchecks).
