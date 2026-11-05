module "member_access" {
  for_each = var.environment_projects
  source   = "../../../../modules/gcp/member-access"

  project_id       = each.value
  org_id           = var.org_id
  group            = var.developer_group
  administrator    = var.administrator
  lift_domain_rule = var.lift_domain_rule

  members = {
    for handle, member in var.org_members_access : handle => {
      account  = coalesce(member.gcp.account, member.email)
      profiles = member.gcp[each.key]
    }
  }
}

# org/gcp/_setup held this policy until now, and forgets it with `removed`.
import {
  for_each = var.environment_projects

  to = module.member_access[each.key].google_iam_deny_policy.no_secret_values
  id = "${urlencode("cloudresourcemanager.googleapis.com/projects/${each.value}")}/medusa-developers-no-secret-values"
}
