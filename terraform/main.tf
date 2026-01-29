# ============================================================================
# Homelab External Infrastructure - Main Configuration
# ============================================================================
# Erstellt:
# - Hetzner vServer
# - Cloudflare DNS Records
# - Deploy Key für GitHub
# - Secrets für die Anwendungen
# ============================================================================

# -----------------------------------------------------------------------------
# Deploy Key für GitHub (private Repo)
# -----------------------------------------------------------------------------
resource "tls_private_key" "deploy_key" {
  algorithm = "ED25519"
}

# -----------------------------------------------------------------------------
# Random Secrets
# -----------------------------------------------------------------------------
resource "random_password" "cookie_secret" {
  length  = 32
  special = false
}

resource "random_password" "healthchecks_secret" {
  length  = 50
  special = false
}

# -----------------------------------------------------------------------------
# SSH Key für Server-Zugang
# -----------------------------------------------------------------------------
resource "hcloud_ssh_key" "default" {
  name       = "${var.server_name}-key"
  public_key = var.ssh_public_key
  labels     = var.tags
}

# -----------------------------------------------------------------------------
# Firewall
# -----------------------------------------------------------------------------
resource "hcloud_firewall" "homelab" {
  name   = "${var.server_name}-firewall"
  labels = var.tags

  # SSH
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # HTTP (für Let's Encrypt Challenge)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # HTTPS
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Headscale DERP/STUN (UDP)
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "3478"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Headscale DERP (TCP Fallback)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "3478"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

# -----------------------------------------------------------------------------
# Cloud-Init Configuration
# -----------------------------------------------------------------------------
locals {
  cloud_init = templatefile("${path.module}/cloud-init.yaml", {
    # GitHub Deploy Key - Base64 encoded um YAML-Probleme zu vermeiden
    deploy_key_private_b64 = base64encode(tls_private_key.deploy_key.private_key_openssh)
    repo_ssh_url           = var.repo_ssh_url

    # Domain
    domain           = var.domain
    subdomain_prefix = var.subdomain_prefix

    # Secrets
    cookie_secret       = random_password.cookie_secret.result
    healthchecks_secret = random_password.healthchecks_secret.result
  })
}

# -----------------------------------------------------------------------------
# Hetzner Server
# -----------------------------------------------------------------------------
resource "hcloud_server" "homelab" {
  name        = var.server_name
  server_type = var.server_type
  location    = var.server_location
  image       = var.server_image
  ssh_keys    = [hcloud_ssh_key.default.id]
  labels      = var.tags

  firewall_ids = [hcloud_firewall.homelab.id]

  user_data = local.cloud_init

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  lifecycle {
    ignore_changes = [user_data]
  }
}

# -----------------------------------------------------------------------------
# Cloudflare DNS Records
# -----------------------------------------------------------------------------

# Headscale Coordination Server
resource "cloudflare_record" "headscale" {
  zone_id = var.cloudflare_zone_id
  name    = "headscale.${var.subdomain_prefix}"
  content = hcloud_server.homelab.ipv4_address
  type    = "A"
  ttl     = 300
  proxied = false # Wichtig: Kein Proxy für Headscale!
}

# Headplane VPN UI
resource "cloudflare_record" "vpn" {
  zone_id = var.cloudflare_zone_id
  name    = "vpn.${var.subdomain_prefix}"
  content = hcloud_server.homelab.ipv4_address
  type    = "A"
  ttl     = 300
  proxied = false
}

# Uptime Kuma Status Page
resource "cloudflare_record" "uptime" {
  zone_id = var.cloudflare_zone_id
  name    = "uptime.${var.subdomain_prefix}"
  content = hcloud_server.homelab.ipv4_address
  type    = "A"
  ttl     = 300
  proxied = false # Besser ohne Proxy für WebSocket
}

# ntfy Push Notifications
resource "cloudflare_record" "ntfy" {
  zone_id = var.cloudflare_zone_id
  name    = "ntfy.${var.subdomain_prefix}"
  content = hcloud_server.homelab.ipv4_address
  type    = "A"
  ttl     = 300
  proxied = false # Kein Proxy für Push
}

# Healthchecks Cronjob Monitoring
resource "cloudflare_record" "hc" {
  zone_id = var.cloudflare_zone_id
  name    = "hc.${var.subdomain_prefix}"
  content = hcloud_server.homelab.ipv4_address
  type    = "A"
  ttl     = 300
  proxied = false
}

# Traefik Dashboard (optional)
resource "cloudflare_record" "traefik" {
  zone_id = var.cloudflare_zone_id
  name    = "traefik.${var.subdomain_prefix}"
  content = hcloud_server.homelab.ipv4_address
  type    = "A"
  ttl     = 300
  proxied = false
}

# -----------------------------------------------------------------------------
# IPv6 Records
# -----------------------------------------------------------------------------
resource "cloudflare_record" "headscale_v6" {
  zone_id = var.cloudflare_zone_id
  name    = "headscale.${var.subdomain_prefix}"
  content = hcloud_server.homelab.ipv6_address
  type    = "AAAA"
  ttl     = 300
  proxied = false
}

resource "cloudflare_record" "vpn_v6" {
  zone_id = var.cloudflare_zone_id
  name    = "vpn.${var.subdomain_prefix}"
  content = hcloud_server.homelab.ipv6_address
  type    = "AAAA"
  ttl     = 300
  proxied = false
}
