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
  # Every plan identity may add a plan under its own stack's prefix. The GCP plans
  # upload as their spoke, which the environment's _setup root grants this, so a
  # hub still holds nothing. The Cloudflare stacks share one plan principal, so it
  # may write under all three of their prefixes.
  plan_store_writers = merge(
    { for stack in ["org", "stg", "prd"] : "setup-${stack}" => { prefix = "plan/setup-${stack}/", member = google_service_account.setup_plan.member } },
    { for k, b in local.direct_plan : k => { prefix = "plan/${b.stack}/", member = b.member } },
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
