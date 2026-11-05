module "plan_store" {
  source = "../../../../modules/gcp/plan-store"

  name       = "${var.management_project_id}-plans"
  project_id = var.management_project_id
  location   = var.region

  labels = {
    env          = "org"
    component    = "plans"
    "managed-by" = "terraform"
  }
}

locals {
  # Every plan identity may add a plan under its own stack's prefix. The GCP
  # plans sign in as their hub, which otherwise holds nothing, and it is the only
  # identity here that is separate per environment: both spokes live outside this
  # root, and the federated principal is shared by stg and prd.
  plan_store_writers = merge(
    { for k, m in module.plan_hub : "gcp-${k}" => { prefix = "${k}/gcp/", member = m.member } },
    { setup = { prefix = "setup/", member = google_service_account.setup_plan.member } },
    local.direct_plan,
  )
}

# Create-only. Pull-request code reaches these identities, and it must not be
# able to read another stack's plan or replace one a reviewer is reading.
resource "google_storage_bucket_iam_member" "plan_store_writers" {
  for_each = local.plan_store_writers

  bucket = module.plan_store.name
  role   = "roles/storage.objectCreator"
  member = each.value.member

  condition {
    title       = "only this stack's plans"
    description = "Create objects under ${each.value.prefix} and nothing else."
    expression  = "resource.name.startsWith('projects/_/buckets/${module.plan_store.name}/objects/${each.value.prefix}')"
  }
}

# The link in the comment opens for a signed-in developer. Only rendered plans:
# a binary plan holds values the rendered text hides.
resource "google_storage_bucket_iam_member" "developers_read_plans" {
  bucket = module.plan_store.name
  role   = "roles/storage.objectViewer"
  member = var.developer_group

  condition {
    title       = "rendered plans only"
    description = "Objects ending in .txt."
    expression  = "resource.name.endsWith('.txt')"
  }
}
