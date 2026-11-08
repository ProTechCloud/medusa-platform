# org/organization-member-access/posthog keeps each person's level now. `removed`
# with `destroy = false`, so the person stays in the organization.
removed {
  from = posthog_organization_member.administrator

  lifecycle {
    destroy = false
  }
}
