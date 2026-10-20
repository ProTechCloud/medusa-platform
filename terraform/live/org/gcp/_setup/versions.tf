terraform {
  # Pinned low enough that a contributor on an older CLI is told so, high
  # enough for the language features used here (terraform_data, optional
  # object attributes). CI pins one exact version; this is the floor.
  required_version = ">= 1.13"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Bucket is supplied at init, not written here: this root creates the very
  # bucket it later stores its state in, so the name cannot be a constant in
  # the file that creates it. First apply runs on local state, then the state
  # is migrated into the bucket it just made.
  backend "gcs" {
    prefix = "org/gcp/setup"
  }
}

provider "google" {
  project = var.management_project_id
  region  = var.region
}
