# ============================================================================
# Homelab External Infrastructure - Outputs
# ============================================================================

# -----------------------------------------------------------------------------
# Server Information
# -----------------------------------------------------------------------------
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
  value       = trimspace(tls_private_key.deploy_key.public_key_openssh)
}

# -----------------------------------------------------------------------------
# DNS URLs
# -----------------------------------------------------------------------------
output "urls" {
  description = "URLs der Dienste (nach vollständiger Konfiguration)"
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
# Diese Secrets werden von Terraform generiert und müssen manuell in die
# .env Datei auf dem Server eingetragen werden.
# -----------------------------------------------------------------------------
output "generated_secrets" {
  description = "Generierte Secrets - in .env auf Server eintragen!"
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
  description = "Nächste Schritte nach dem Terraform Deployment"
  value       = <<-EOT

    ============================================================
    TERRAFORM DEPLOYMENT ABGESCHLOSSEN
    ============================================================

    Der Server ist provisioniert mit:
    - Docker installiert
    - Firewall konfiguriert (SSH, HTTP, HTTPS, Headscale)
    - Daten-Verzeichnis unter /opt/homelab-data/ erstellt

    ============================================================
    MANUELLE KONFIGURATION ERFORDERLICH
    ============================================================

    1. DEPLOY KEY BEI GITHUB HINZUFÜGEN:
       - Gehe zu: GitHub Repo → Settings → Deploy keys → Add deploy key
       - Title: "Homelab Server"
       - Key: Siehe Output "github_deploy_key"
       - Allow write access: NEIN (nur read)

    2. SSH ZUM SERVER:
       ssh root@${hcloud_server.homelab.ipv4_address}

    3. CLOUD-INIT ABWARTEN (ca. 2-3 Minuten):
       tail -f /var/log/cloud-init-output.log
       # Warten bis "Cloud-Init abgeschlossen" erscheint

    4. REPOSITORY KLONEN UND SYMLINKS ERSTELLEN:
       git clone <REPO_SSH_URL> /opt/homelab-repo
       ln -s /opt/homelab-repo/hetzner /opt/homelab
       ln -s /opt/homelab-data /opt/homelab/data

    5. .ENV DATEI ERSTELLEN:
       cd /opt/homelab
       cp .env.example .env
       nano .env
       # Secrets mit: terraform output -json generated_secrets

    6. CONFIGS ANPASSEN:
       # PostgreSQL Passwort in headscale/config.yaml eintragen
       # Cookie Secret in headplane/config.yaml eintragen

    7. DOCKER COMPOSE STARTEN:
       cd /opt/homelab && docker compose up -d

    8. HEADSCALE KONFIGURIEREN:
       docker exec headscale headscale users create homelab
       docker exec headscale headscale apikeys create --expiration 365d
       # API Key in .env eintragen, dann:
       docker compose restart headplane

    ============================================================
    DETAILLIERTE ANLEITUNG: Siehe hetzner/SETUP.md im Repository
    ============================================================
  EOT
}
