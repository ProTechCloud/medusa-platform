# PostHog cannot invite through the API, so each person accepts an invitation by
# hand first. This root only adopts them and keeps them at their level.

locals {
  # Keyed by handle, which says nothing about who the person is.
  handles = nonsensitive(toset([
    for handle, member in var.org_members_access : handle
    if member.posthog != null && lower(member.email) != lower(var.owner_email)
  ]))
}

data "posthog_user" "member" {
  for_each = local.handles

  email = var.org_members_access[each.key].email
}

# Once applied the import is a no-op.
import {
  for_each = local.handles

  to = posthog_organization_member.member[each.key]
  id = "${var.organization_id}/${data.posthog_user.member[each.key].uuid}"
}

# retain_on_destroy: by default, destroying this resource removes the person from
# the organization. Taking someone off the list should stop managing their level,
# not lock them out.
resource "posthog_organization_member" "member" {
  for_each = local.handles

  user_uuid         = data.posthog_user.member[each.key].uuid
  level             = var.org_members_access[each.key].posthog
  retain_on_destroy = true
}
