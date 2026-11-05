data "posthog_user" "administrator" {
  email = var.administrator_email
}

# retain_on_destroy: by default, destroying this resource removes the person
# from the organization. Taking it out of Terraform should stop managing their
# level, not lock them out.
resource "posthog_organization_member" "administrator" {
  user_uuid         = data.posthog_user.administrator.uuid
  level             = "admin"
  retain_on_destroy = true
}
