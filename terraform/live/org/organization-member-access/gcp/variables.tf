variable "org_id" {
  type = string
}

variable "management_project_id" {
  type = string
}

variable "environment_projects" {
  description = "Project id per environment."
  type        = map(string)
}

variable "developer_group" {
  type = string
}

variable "administrator" {
  type = string
}

variable "lift_domain_rule" {
  description = "Whether the organization sets iam.allowedPolicyMemberDomains, which each project then has to lift."
  type        = bool
  default     = false
}

variable "org_members_access" {
  description = "ORG_MEMBERS_ACCESS: who may use GCP and PostHog, keyed by a short handle. `account` is set when the Google account's primary address differs from `email`."
  type = map(object({
    email = string
    gcp = optional(object({
      account = optional(string)
      stg     = optional(list(string), [])
      prd     = optional(list(string), [])
    }), {})
    posthog = optional(string)
  }))
  sensitive = true

  validation {
    condition = alltrue(flatten([
      for member in values(var.org_members_access) : [
        for profile in concat(member.gcp.stg, member.gcp.prd) : contains(["read_only", "administration", "logs"], profile)
      ]
    ]))
    error_message = "A GCP profile must be read_only, administration or logs."
  }

  validation {
    condition = alltrue([
      for member in values(var.org_members_access) : member.posthog == null || contains(["member", "admin"], coalesce(member.posthog, "member"))
    ])
    error_message = "A PostHog level must be member or admin."
  }

  validation {
    condition = (
      length(distinct([for member in values(var.org_members_access) : lower(coalesce(member.gcp.account, member.email))]))
      == length(var.org_members_access)
    )
    error_message = "Each person's address may appear only once."
  }
}
