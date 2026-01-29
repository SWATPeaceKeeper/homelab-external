# ============================================================================
# Homelab External Infrastructure - Variables
# ============================================================================
# Alle Werte werden über GitHub Secrets/Environment Variables übergeben.
# Defaults sind für Werte gesetzt, die sich selten ändern.
# ============================================================================

# -----------------------------------------------------------------------------
# Provider Credentials (GitHub Secrets)
# -----------------------------------------------------------------------------
variable "hetzner_token" {
  description = "Hetzner Cloud API Token"
  type        = string
  sensitive   = true
}

variable "cloudflare_api_token" {
  description = "Cloudflare API Token (mit DNS Edit Permissions)"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID für die Domain"
  type        = string
}

# -----------------------------------------------------------------------------
# Repository (GitHub Secret: REPO_SSH_URL)
# -----------------------------------------------------------------------------
variable "repo_ssh_url" {
  description = "GitHub Repository URL (SSH Format für Deploy Key)"
  type        = string
  # Wird als GitHub Secret übergeben
}

# -----------------------------------------------------------------------------
# Domain Configuration (Defaults - im Repo festgelegt)
# -----------------------------------------------------------------------------
variable "domain" {
  description = "Hauptdomain"
  type        = string
  default     = "robinwerner.net"
}

variable "subdomain_prefix" {
  description = "Subdomain-Prefix für Homelab-Dienste"
  type        = string
  default     = "homelab" # → headscale.homelab.robinwerner.net
}

# -----------------------------------------------------------------------------
# Server Configuration (Defaults - im Repo festgelegt)
# -----------------------------------------------------------------------------
variable "server_name" {
  description = "Name des Hetzner Servers"
  type        = string
  default     = "homelab-external"
}

variable "server_type" {
  description = "Hetzner Server Typ"
  type        = string
  default     = "cx22" # 2 vCPU, 4 GB RAM, 40 GB SSD - ca. 5 EUR/Monat
}

variable "server_location" {
  description = "Hetzner Datacenter Location"
  type        = string
  default     = "fsn1" # Falkenstein
}

variable "server_image" {
  description = "Server OS Image"
  type        = string
  default     = "ubuntu-24.04"
}

# -----------------------------------------------------------------------------
# SSH Key (GitHub Secret: SSH_PUBLIC_KEY)
# -----------------------------------------------------------------------------
variable "ssh_public_key" {
  description = "SSH Public Key für Server-Zugang (Inhalt, nicht Pfad)"
  type        = string
  # Wird als GitHub Secret übergeben
}

# -----------------------------------------------------------------------------
# Tags (Defaults)
# -----------------------------------------------------------------------------
variable "tags" {
  description = "Labels für Hetzner Ressourcen"
  type        = map(string)
  default = {
    project     = "homelab"
    environment = "production"
    managed_by  = "terraform"
  }
}
