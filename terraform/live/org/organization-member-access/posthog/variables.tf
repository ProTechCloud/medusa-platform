variable "organization_id" {
  description = "UUID of the medusa organization."
  type        = string
}

variable "owner_email" {
  description = "The organization's owner. Their level is neither member nor admin, so they are left alone even when listed."
  type        = string
  sensitive   = true
}

variable "org_members_access" {
  description = "ORG_MEMBERS_ACCESS: who may use GCP and PostHog, keyed by a short handle."
  type = map(object({
    email   = string
    posthog = optional(string)
  }))
  sensitive = true

  validation {
    condition = alltrue([
      for member in values(var.org_members_access) : member.posthog == null || contains(["member", "admin"], coalesce(member.posthog, "member"))
    ])
    error_message = "A PostHog level must be member or admin."
  }

  validation {
    condition     = length(distinct([for member in values(var.org_members_access) : lower(member.email)])) == length(var.org_members_access)
    error_message = "Each person's address may appear only once."
  }
}
