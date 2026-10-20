# Developer access is granted here, on both environment projects, because the
# group is a single fact about the organization rather than something each
# environment decides for itself.
#
# The IAP condition names an instance that does not exist yet — the workload
# root creates it later. IAM conditions match on resource name, not on a
# resource that must already be there, so this is safe and keeps the grant
# narrow from the first day instead of being widened "temporarily".
module "developer_access" {
  for_each = var.environment_projects
  source   = "../../../../modules/gcp/developer-access"

  project_id     = each.value
  project_number = module.environment_project[each.key].number
  group          = var.developer_group

  server_access_instance = "medusa-${each.key}"
  zone                   = var.zone

  depends_on = [module.environment_project]
}
