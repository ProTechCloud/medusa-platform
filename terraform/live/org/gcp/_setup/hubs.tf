# ---------- GCP: a plan hub and an apply hub per environment ----------
# A hub holds no permissions. Its only capability is granted by the spoke in
# the environment project, which trusts this hub and nothing else.

module "plan_hub" {
  for_each = var.environment_projects
  source   = "../../../../modules/gcp/wif-hub"

  project_id  = var.management_project_id
  name        = "medusa-${each.key}-plan-hub"
  description = "CI plan entry point for ${each.key}"

  pool_name      = google_iam_workload_identity_pool.github.name
  attribute      = "plan_entry"
  allowed_values = local.plan_entries
}

module "apply_hub" {
  for_each = var.environment_projects
  source   = "../../../../modules/gcp/wif-hub"

  project_id  = var.management_project_id
  name        = "medusa-${each.key}-apply-hub"
  description = "CI apply entry point for ${each.key}"

  pool_name      = google_iam_workload_identity_pool.github.name
  attribute      = "apply_entry"
  allowed_values = local.apply_entries[each.key]
}

# ---------- the application's deploy identity ----------
# Same shape as the others: the backend federates to a hub here, and the spoke
# that lets it push images and roll out the VM lives in the stg project.
module "backend_deploy_hub" {
  source = "../../../../modules/gcp/wif-hub"

  project_id  = var.management_project_id
  name        = "medusa-stg-deploy-hub"
  description = "medusa-backend deploy entry point"

  pool_name      = google_iam_workload_identity_pool.github.name
  attribute      = "apply_entry"
  allowed_values = local.backend_deploy_entries
}

module "tunnel_token_hub" {
  source = "../../../../modules/gcp/wif-hub"

  project_id  = var.management_project_id
  name        = "medusa-stg-tunnel-token-hub"
  description = "Entry point for the stg-cd step that writes the tunnel token"

  pool_name      = google_iam_workload_identity_pool.github.name
  attribute      = "apply_entry"
  allowed_values = local.tunnel_token_entries
}

# ---------- Cloudflare: identities that only reach state ----------
# These never touch Cloudflare with a Google credential. The Cloudflare API
# token is minted per job and revoked at the end; all these identities do is
# read and write the Cloudflare roots' state, which lives in the management
# bucket. They are therefore plain federated accounts, with no spoke.

resource "google_service_account" "cloudflare_plan" {
  for_each = local.cloudflare_apply_entries

  project      = var.management_project_id
  account_id   = "medusa-cf-${each.key}-plan"
  display_name = "Cloudflare plan (${each.key})"
  description  = "Reads the ${each.key} Cloudflare state. Holds no Cloudflare credential."
}

resource "google_service_account" "cloudflare_apply" {
  for_each = local.cloudflare_apply_entries

  project      = var.management_project_id
  account_id   = "medusa-cf-${each.key}-apply"
  display_name = "Cloudflare apply (${each.key})"
  description  = "Writes the ${each.key} Cloudflare state. Holds no Cloudflare credential."
}

resource "google_service_account_iam_member" "cloudflare_plan_federated" {
  for_each = {
    for pair in setproduct(keys(local.cloudflare_apply_entries), local.cloudflare_plan_entries) :
    "${pair[0]}|${pair[1]}" => { env = pair[0], entry = pair[1] }
  }

  service_account_id = google_service_account.cloudflare_plan[each.value.env].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.plan_entry/${each.value.entry}"
}

resource "google_service_account_iam_member" "cloudflare_apply_federated" {
  for_each = {
    for env, entries in local.cloudflare_apply_entries : env => entries[0]
  }

  service_account_id = google_service_account.cloudflare_apply[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.apply_entry/${each.value}"
}
