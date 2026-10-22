# Developer access is granted here, on both environment projects, because the
# group is a single fact about the organization rather than something each
# environment decides for itself.
#
# The server-access tunnel grant is the exception: it names the API instance,
# which this root runs before. It lives in the workload root, which creates
# the VM, and reads the group from this root's output.
module "developer_access" {
  for_each = var.environment_projects
  source   = "../../../../modules/gcp/developer-access"

  project_id = each.value
  group      = var.developer_group

  depends_on = [module.environment_project]
}
