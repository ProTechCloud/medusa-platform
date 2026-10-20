# ---------- plan: reads everything, changes nothing ----------
# It still needs to write: Terraform's GCS backend takes a lock by writing an
# object, and a plan that cannot release its lock wedges every run after it.
module "plan_spoke" {
  source = "../../../../modules/gcp/wif-spoke"

  project_id  = var.project_id
  name        = "medusa-plan"
  description = "Terraform plan for ${var.environment}. Read-only, no secret values."
  hub_member  = local.plan_hub

  roles = [
    { role = "roles/viewer" },
  ]
}

resource "google_storage_bucket_iam_member" "plan_state" {
  bucket = module.state.name
  role   = "roles/storage.objectAdmin"
  member = module.plan_spoke.member
}

resource "google_kms_crypto_key_iam_member" "plan_state_key" {
  crypto_key_id = module.state.kms_key_id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = module.plan_spoke.member
}

# ---------- apply: changes infrastructure, not itself ----------
module "apply_spoke" {
  source = "../../../../modules/gcp/wif-spoke"

  project_id  = var.project_id
  name        = "medusa-apply"
  description = "Terraform apply for ${var.environment}."
  hub_member  = local.apply_hub

  roles = [
    { role = "roles/compute.admin" },
    { role = "roles/artifactregistry.admin" },
    { role = "roles/secretmanager.admin" },
    { role = "roles/iap.admin" },
    { role = "roles/serviceusage.serviceUsageAdmin" },

    # Project-level bindings are part of applying the stack (the instance
    # needs logWriter), but projectIamAdmin unconditionally would let the
    # apply grant itself owner. The condition limits it to the exact roles
    # this stack binds, so a request to grant anything else is refused by IAM
    # rather than caught in review.
    {
      role  = "roles/resourcemanager.projectIamAdmin"
      title = "only the roles this stack binds"
      expression = join("", [
        "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', [])",
        ".hasOnly(['roles/logging.logWriter', 'roles/monitoring.metricWriter'])",
      ])
    },

    # Creating the instance's service account is part of applying the stack,
    # so this cannot be withheld entirely. Narrowing it to the stack's own
    # naming prefix stops the apply from minting an identity outside it.
    {
      role       = "roles/iam.serviceAccountAdmin"
      title      = "only medusa-prefixed service accounts"
      expression = "resource.name.contains('/serviceAccounts/medusa-')"
    },
  ]
}

resource "google_storage_bucket_iam_member" "apply_state" {
  bucket = module.state.name
  role   = "roles/storage.objectAdmin"
  member = module.apply_spoke.member
}

resource "google_kms_crypto_key_iam_member" "apply_state_key" {
  crypto_key_id = module.state.kms_key_id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = module.apply_spoke.member
}

# ---------- tunnel-token writer: one secret, nothing else ----------
# Exists so the tunnel token never passes through Terraform. The deploy job
# fetches it from Cloudflare and writes it here; an identity that can write
# exactly one secret is a far smaller thing to leak than a state file holding
# the value in clear text.
module "tunnel_token_writer" {
  source = "../../../../modules/gcp/wif-spoke"

  project_id  = var.project_id
  name        = "medusa-tunnel-token"
  description = "Writes new versions of the tunnel-token secret. Nothing else."
  hub_member  = local.apply_hub
}
