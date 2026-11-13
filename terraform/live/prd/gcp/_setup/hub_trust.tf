# Lets this environment's workload root hold the trust rules of its hubs. The
# hubs stay in the management project; only who may become them is decided from
# here. Authoritative, so a second holder of either role shows as a diff.
locals {
  # Only stg has a deploy hub: the application deploys to stg and nowhere else.
  hubs = var.environment == "stg" ? { backend_deploy = local.org.backend_deploy_hub_name } : {}
}

resource "google_service_account_iam_binding" "apply_edits_hub_trust" {
  for_each = local.hubs

  service_account_id = each.value
  role               = local.org.hub_trust_role
  members            = [module.apply_spoke.member]
}

# Read only, for the refresh: plan runs on pull-request code, so it can never
# set a rule.
resource "google_service_account_iam_binding" "plan_reads_hub_trust" {
  for_each = local.hubs

  service_account_id = each.value
  role               = "roles/iam.serviceAccountViewer"
  members            = [module.plan_spoke.member]
}
