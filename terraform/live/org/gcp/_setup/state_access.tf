# The Cloudflare roots keep their state in the management bucket, so these are
# the only identities besides a person that touch it. objectAdmin rather than
# objectCreator: Terraform must also be able to delete the lock object it
# wrote, and a plan that cannot release its lock wedges the next run.

locals {
  # The exact object prefix each Cloudflare identity may touch, with the
  # trailing slash: `stg/cloudflare` without it also matches a future
  # `stg/cloudflare-anything`, so the match has to stop at a path segment.
  #
  # org is spelled out rather than derived. Its two roots sit side by side —
  # org/cloudflare/live and org/cloudflare/setup — so a prefix of
  # `org/cloudflare/` would hand the _setup state to these identities, and the
  # plan one is reachable from pull-request code.
  cloudflare_state_prefix = {
    org = "org/cloudflare/live/"
    stg = "stg/cloudflare/"
    prd = "prd/cloudflare/"
  }
}
resource "google_storage_bucket_iam_member" "cloudflare_state" {
  for_each = merge(
    { for env, sa in google_service_account.cloudflare_plan : "plan-${env}" => { email = sa.email, env = env } },
    { for env, sa in google_service_account.cloudflare_apply : "apply-${env}" => { email = sa.email, env = env } },
  )

  bucket = module.management_state.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${each.value.email}"

  # Scoped to this stack's own prefix. Granted bucket-wide, as it was, these
  # identities could read and overwrite org/gcp/setup and the environment
  # _setup states — the files that record who is allowed to do what. The plan
  # identities are reachable from pull-request code, so that was a path from
  # an unreviewed branch to tampering with the identity records themselves.
  condition {
    title       = "only this stack's state"
    description = "Objects under ${local.cloudflare_state_prefix[each.value.env]} and nothing else."
    expression  = "resource.name.startsWith('projects/_/buckets/${module.management_state.name}/objects/${local.cloudflare_state_prefix[each.value.env]}')"
  }
}

# Listing is a bucket operation, not an object one, so the prefix condition
# above cannot cover it — and Terraform's GCS backend lists the bucket on init
# to enumerate workspaces. Without this the identity can read its own state
# but cannot discover that it exists, and init fails before any plan runs.
#
# legacyBucketReader is the smallest predefined role that carries
# storage.objects.list. It exposes object *names* across the bucket, which
# reveals the layout of the stacks and nothing about their contents.
resource "google_storage_bucket_iam_member" "cloudflare_state_list" {
  for_each = merge(
    { for env, sa in google_service_account.cloudflare_plan : "plan-${env}" => sa.email },
    { for env, sa in google_service_account.cloudflare_apply : "apply-${env}" => sa.email },
  )

  bucket = module.management_state.name
  role   = "roles/storage.legacyBucketReader"
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
