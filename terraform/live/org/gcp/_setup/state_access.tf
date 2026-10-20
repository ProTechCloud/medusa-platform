# The Cloudflare roots keep their state in the management bucket, so these are
# the only identities besides a person that touch it. objectAdmin rather than
# objectCreator: Terraform must also be able to delete the lock object it
# wrote, and a plan that cannot release its lock wedges the next run.
resource "google_storage_bucket_iam_member" "cloudflare_state" {
  for_each = merge(
    { for env, sa in google_service_account.cloudflare_plan : "plan-${env}" => sa.email },
    { for env, sa in google_service_account.cloudflare_apply : "apply-${env}" => sa.email },
  )

  bucket = module.management_state.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${each.value}"
}

# Reading an object from a CMEK bucket decrypts with the key, which is a
# separate permission from reading the object.
resource "google_kms_crypto_key_iam_member" "cloudflare_state_key" {
  for_each = merge(
    { for env, sa in google_service_account.cloudflare_plan : "plan-${env}" => sa.email },
    { for env, sa in google_service_account.cloudflare_apply : "apply-${env}" => sa.email },
  )

  crypto_key_id = module.management_state.kms_key_id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${each.value}"
}
