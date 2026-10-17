terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Remote state so CI and laptops share one state file and one lock. Without
  # it CI starts empty and tries to recreate resources that already exist.
  # The bucket itself is managed in gcp_tfstate.tf — it had to be created with
  # local state first, then this block enabled via `init -migrate-state`.
  backend "gcs" {
    bucket = "project-78c2f5ca-96f0-47c0-ad0-tfstate"
    prefix = "platform"
  }
}
