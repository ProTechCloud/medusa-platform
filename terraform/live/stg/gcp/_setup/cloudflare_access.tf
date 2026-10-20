# The Cloudflare roots read this environment's workload state to learn the
# hostname and port they must route to. Read-only: they publish DNS, they do
# not change infrastructure here.
locals {
  cloudflare_readers = [
    local.org.cloudflare_plan_identities[var.environment],
    local.org.cloudflare_apply_identities[var.environment],
  ]
}

resource "google_storage_bucket_iam_member" "cloudflare_reads_state" {
  for_each = toset(local.cloudflare_readers)

  bucket = module.state.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${each.value}"
}

resource "google_kms_crypto_key_iam_member" "cloudflare_decrypts_state" {
  for_each = toset(local.cloudflare_readers)

  crypto_key_id = module.state.kms_key_id
  role          = "roles/cloudkms.cryptoKeyDecrypter"
  member        = "serviceAccount:${each.value}"
}
