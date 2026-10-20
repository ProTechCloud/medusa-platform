# The workload root reads this root's outputs through remote state, and that
# state lives in the management bucket. Read-only, and only this environment's
# prefix matters to it — but GCS grants at bucket scope, so the narrowing that
# counts is the deny policy, not this binding.
locals {
  env_spokes = [module.plan_spoke.email, module.apply_spoke.email]
}

resource "google_storage_bucket_iam_member" "spokes_read_management" {
  for_each = toset(local.env_spokes)

  bucket = var.management_state_bucket
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${each.value}"
}

resource "google_kms_crypto_key_iam_member" "spokes_decrypt_management" {
  for_each = toset(local.env_spokes)

  crypto_key_id = local.org.management_state_key
  role          = "roles/cloudkms.cryptoKeyDecrypter"
  member        = "serviceAccount:${each.value}"
}
