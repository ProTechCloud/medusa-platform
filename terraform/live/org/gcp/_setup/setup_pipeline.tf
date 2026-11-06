# How the _setup roots reach CI: a plan on every pull request, an apply on merge
# behind a required reviewer. The hand path in the README stays for the first
# apply of an organization and for emergencies.

locals {
  setup_projects = merge(var.environment_projects, { org = var.management_project_id })
}

# ---------- plan ----------
# A plain account, not a hub and a spoke: one identity reads all three projects,
# so there is no environment for a spoke to live in. It runs on pull-request
# code, so it holds only reads, and the deny in each environment's _setup root
# refuses it secret values.
resource "google_service_account" "setup_plan" {
  account_id   = "medusa-setup-plan"
  project      = var.management_project_id
  display_name = "Terraform plan for the _setup roots"
  description  = "Terraform plan for the _setup roots. Read-only, no secret values."
}

resource "google_service_account_iam_binding" "setup_plan_trust" {
  service_account_id = google_service_account.setup_plan.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    for entry in local.setup_plan_entries :
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.plan_entry/${entry}"
  ]
}

# Never roles/viewer: that role grows as Google adds permissions, and this one
# has to stay the reads a refresh of these three roots performs.
resource "google_project_iam_custom_role" "setup_refresh" {
  for_each = local.setup_projects

  project     = each.value
  role_id     = "medusaSetupRefresh"
  title       = "Medusa setup refresh"
  description = "The reads a Terraform refresh of the _setup roots performs. Held by the setup plan."
  permissions = [
    "cloudkms.cryptoKeys.get",
    "cloudkms.cryptoKeys.getIamPolicy",
    "cloudkms.keyRings.get",
    "iam.denypolicies.get",
    "iam.roles.get",
    "iam.serviceAccounts.get",
    "iam.serviceAccounts.getIamPolicy",
    "iam.workloadIdentityPoolProviders.get",
    "iam.workloadIdentityPools.get",
    "resourcemanager.projects.get",
    "resourcemanager.projects.getIamPolicy",
    "serviceusage.services.get",
    "serviceusage.services.list",
    "storage.buckets.get",
    "storage.buckets.getIamPolicy",
  ]

  depends_on = [module.environment_project]
}

resource "google_project_iam_member" "setup_plan_refreshes" {
  for_each = local.setup_projects

  project = each.value
  role    = google_project_iam_custom_role.setup_refresh[each.key].id
  member  = google_service_account.setup_plan.member
}

resource "google_project_iam_member" "setup_plan_reads_org_policy" {
  for_each = local.setup_projects

  project = each.value
  role    = "roles/orgpolicy.policyViewer"
  member  = google_service_account.setup_plan.member

  depends_on = [module.environment_project]
}

# The three _setup states and nothing else in the bucket. org/cloudflare/setup
# holds a token value, so it stays out, and so does every workload state.
resource "google_storage_bucket_iam_member" "setup_plan_reads_state" {
  for_each = toset(["org/gcp/setup/", "stg/gcp/setup/", "prd/gcp/setup/"])

  bucket = module.management_state.name
  role   = "roles/storage.objectViewer"
  member = google_service_account.setup_plan.member

  condition {
    title       = "only this setup state"
    description = "Objects under ${each.value} and nothing else."
    expression  = "resource.name.startsWith('projects/_/buckets/${module.management_state.name}/objects/${each.value}')"
  }
}

resource "google_storage_bucket_iam_member" "setup_plan_lists_state" {
  bucket = module.management_state.name
  role   = "roles/storage.legacyBucketReader"
  member = google_service_account.setup_plan.member
}

resource "google_kms_crypto_key_iam_member" "setup_plan_state_key" {
  crypto_key_id = module.management_state.kms_key_id
  role          = "roles/cloudkms.cryptoKeyDecrypter"
  member        = google_service_account.setup_plan.member
}

# ---------- apply ----------
# The bootstrap admin's one federated path. It holds owner on the management
# project, so this binding is authoritative: a second workflow or environment
# that could become it shows as a diff here.
resource "google_service_account_iam_binding" "bootstrap_admin_trust" {
  service_account_id = "projects/${var.management_project_id}/serviceAccounts/${local.bootstrap_admin}"
  role               = "roles/iam.workloadIdentityUser"
  members = [
    for entry in local.setup_apply_entries :
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.apply_entry/${entry}"
  ]
}
