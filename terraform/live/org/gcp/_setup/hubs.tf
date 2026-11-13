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
# that lets it push images and roll out the API's service lives in the stg
# project.
#
# This hub holds no trust rule in this root. The rule names a workflow and an
# environment, which change with the workload, so it is in the stg workload
# root, in trust.tf.
resource "google_service_account" "backend_deploy_hub" {
  account_id   = "medusa-stg-deploy-hub"
  project      = var.management_project_id
  display_name = "medusa-app deploy entry point"
  description  = "medusa-app deploy entry point"
}

moved {
  from = module.backend_deploy_hub.google_service_account.hub
  to   = google_service_account.backend_deploy_hub
}

# `removed` with `destroy = false`: destroying it would stop the deploy
# between this apply and the workload root's, which takes the same member over.
removed {
  from = module.backend_deploy_hub.google_service_account_iam_member.federated

  lifecycle {
    destroy = false
  }
}

# What the workload root needs to hold that rule on a hub, and nothing more.
# The environment's _setup root grants it to the apply spoke, per hub.
resource "google_project_iam_custom_role" "hub_trust_editor" {
  project     = var.management_project_id
  role_id     = "medusaHubTrustEditor"
  title       = "Medusa hub trust editor"
  description = "Read a hub and set who may become it. Held by an environment's apply spoke on that environment's hubs."
  permissions = [
    "iam.serviceAccounts.get",
    "iam.serviceAccounts.getIamPolicy",
    "iam.serviceAccounts.setIamPolicy",
  ]
}
