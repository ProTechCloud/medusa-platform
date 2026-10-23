# Human access is granted here, on both environment projects, because who may
# look and who may act are single facts about the organization rather than
# something each environment decides for itself.
module "human_access" {
  for_each = var.environment_projects
  source   = "../../../../modules/gcp/developer-access"

  project_id    = each.value
  group         = var.developer_group
  administrator = var.administrator

  depends_on = [module.environment_project]
}
