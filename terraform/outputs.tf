# ============================================================================
# Homelab External Infrastructure - Outputs
# ============================================================================

output "server_ipv4" {
  description = "IPv4 Adresse des Hetzner Servers"
  value       = hcloud_server.homelab.ipv4_address
}

output "server_ipv6" {
  description = "IPv6 Adresse des Hetzner Servers"
  value       = hcloud_server.homelab.ipv6_address
}

output "server_status" {
  description = "Server Status"
  value       = hcloud_server.homelab.status
}

output "ssh_command" {
  description = "SSH Befehl zum Verbinden"
  value       = "ssh root@${hcloud_server.homelab.ipv4_address}"
}

# -----------------------------------------------------------------------------
# Deploy Key für GitHub
# -----------------------------------------------------------------------------
output "github_deploy_key" {
  description = "Public Key für GitHub Deploy Key (diesen bei GitHub hinzufügen!)"
  value       = tls_private_key.deploy_key.public_key_openssh
}

# -----------------------------------------------------------------------------
# DNS URLs
# -----------------------------------------------------------------------------
output "urls" {
  description = "URLs der Dienste"
  value = {
    headscale    = "https://headscale.${var.subdomain_prefix}.${var.domain}"
    vpn_ui       = "https://vpn.${var.subdomain_prefix}.${var.domain}"
    uptime_kuma  = "https://uptime.${var.subdomain_prefix}.${var.domain}"
    ntfy         = "https://ntfy.${var.subdomain_prefix}.${var.domain}"
    healthchecks = "https://hc.${var.subdomain_prefix}.${var.domain}"
    traefik      = "https://traefik.${var.subdomain_prefix}.${var.domain}"
  }
}

# -----------------------------------------------------------------------------
# Generierte Secrets
# -----------------------------------------------------------------------------
output "generated_secrets" {
  description = "Generierte Secrets (werden automatisch in .env auf Server geschrieben)"
  sensitive   = true
  value = {
    cookie_secret       = random_password.cookie_secret.result
    healthchecks_secret = random_password.healthchecks_secret.result
  }
}

# -----------------------------------------------------------------------------
# Nächste Schritte
# -----------------------------------------------------------------------------
output "next_steps" {
  description = "Nächste Schritte nach dem Deployment"
  value       = <<-EOT

    ============================================================
    NÄCHSTE SCHRITTE
    ============================================================

    1. WICHTIG - Deploy Key bei GitHub hinzufügen:
       - Gehe zu: GitHub Repo → Settings → Deploy keys → Add deploy key
       - Title: "Homelab Server"
       - Key: (siehe output "github_deploy_key")
       - Allow write access: NEIN (nur read)

    2. SSH zum Server:
       ssh root@${hcloud_server.homelab.ipv4_address}

    3. Warte bis Cloud-Init fertig ist (2-3 Minuten):
       tail -f /var/log/cloud-init-output.log

    4. Prüfe ob alle Container laufen:
       cd /opt/homelab && docker compose ps

    5. Headscale Namespace erstellen:
       docker exec headscale headscale namespaces create homelab

    6. API-Key für Headplane generieren:
       docker exec headscale headscale apikeys create --expiration 365d

    7. API-Key in /opt/homelab/.env eintragen:
       nano /opt/homelab/.env
       # HEADSCALE_API_KEY=<dein-key>

    8. Container neu starten:
       docker compose down && docker compose up -d

    9. Services testen:
       - https://headscale.${var.subdomain_prefix}.${var.domain}
       - https://vpn.${var.subdomain_prefix}.${var.domain}
       - https://uptime.${var.subdomain_prefix}.${var.domain}

    ============================================================
  EOT
}
