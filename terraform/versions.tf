# ============================================================================
# Homelab External Infrastructure - Terraform Configuration
# ============================================================================

terraform {
  required_version = ">= 1.5.0"

  # ---------------------------------------------------------------------------
  # Backend: Hetzner Object Storage (S3-kompatibel)
  # ---------------------------------------------------------------------------
  # WICHTIG: Bucket muss vorher manuell erstellt werden!
  # Credentials werden via Environment Variables übergeben:
  #   - AWS_ACCESS_KEY_ID
  #   - AWS_SECRET_ACCESS_KEY
  # ---------------------------------------------------------------------------
  backend "s3" {
    bucket = "homelab-external-terraform-state"
    key    = "homelab-external/terraform.tfstate"
    region = "eu-central-1"

    endpoints = {
      s3 = "https://fsn1.your-objectstorage.com"
    }

    # Wichtig für S3-kompatible Storages
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.20"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "hcloud" {
  token = var.hetzner_token
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
