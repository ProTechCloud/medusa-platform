# Full plan text for the pull-request comment, which cuts a long plan. The
# bucket is separate from state on purpose: a developer may read a rendered plan
# here without coming near the state files, which hold more than a plan shows.

# Its own key, like every state bucket. The management project refuses a bucket
# without a customer-managed key.
resource "google_kms_key_ring" "plans" {
  name     = "${var.name}-plans"
  project  = var.project_id
  location = var.location
}

resource "google_kms_crypto_key" "plans" {
  name     = "plans"
  key_ring = google_kms_key_ring.plans.id
  purpose  = "ENCRYPT_DECRYPT"

  rotation_period = "${var.key_rotation_days * 24 * 60 * 60}s"

  lifecycle {
    prevent_destroy = true
  }
}

# GCS encrypts with the key as itself, not as the caller, so the identities that
# write and read plans need no grant on the key.
data "google_storage_project_service_account" "gcs" {
  project = var.project_id
}

resource "google_kms_crypto_key_iam_member" "gcs_agent" {
  crypto_key_id = google_kms_crypto_key.plans.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${data.google_storage_project_service_account.gcs.email_address}"
}

resource "google_storage_bucket" "plans" {
  name     = var.name
  project  = var.project_id
  location = var.location
  labels   = var.labels

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  encryption {
    default_kms_key_name = google_kms_crypto_key.plans.id
  }

  # A plan is worth reading while its pull request is open.
  lifecycle_rule {
    condition {
      age = var.retention_days
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_kms_crypto_key_iam_member.gcs_agent]
}

# A new bucket gives project viewers this role, which reads every object. Anyone
# with roles/viewer on the project would read every plan, whatever the grants on
# the bucket say. Empty and authoritative, so it stays that way.
resource "google_storage_bucket_iam_binding" "no_legacy_object_reader" {
  bucket  = google_storage_bucket.plans.name
  role    = "roles/storage.legacyObjectReader"
  members = []
}
