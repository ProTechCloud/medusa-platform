terraform {
  required_version = ">= 1.13"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Workload state lives in the environment's own bucket, not the management
  # one. The identities that grant access to this environment are recorded in
  # the management bucket, which this root's credentials cannot read.
  backend "gcs" {
    prefix = "stg/gcp/live"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}
