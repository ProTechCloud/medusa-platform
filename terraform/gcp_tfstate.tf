# Remote state. Without this, CI starts from an empty state file and tries to
# create resources that already exist — every apply fails on "already exists".
#
# Bootstrap order matters: this bucket must exist before `terraform init`
# can point its backend at it, so it is created with local state first and the
# backend block in versions.tf is enabled afterwards (`terraform init -migrate-state`).

resource "google_storage_bucket" "tfstate" {
  project  = var.gcp_project_id
  name     = "${var.gcp_project_id}-tfstate"
  location = var.gcp_region

  # Terraform state is the one artifact whose history you genuinely need:
  # a corrupted apply is recoverable only by rolling back to a prior version.
  versioning {
    enabled = true
  }

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  lifecycle_rule {
    condition {
      num_newer_versions = 20
    }
    action {
      type = "Delete"
    }
  }

  labels = local.common_labels

  depends_on = [google_project_service.enabled]
}

resource "google_storage_bucket_iam_member" "terraform_ci_state" {
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.terraform_ci.email}"
}
