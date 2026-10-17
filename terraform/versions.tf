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

  # Remote state lives in GCS so CI and laptops share one lock.
  # Bootstrap note: the bucket must exist before the first `init`.
  # backend "gcs" {
  #   bucket = "medusa-tfstate-<project>"
  #   prefix = "platform"
  # }
}
