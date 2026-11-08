variable "project_id" {
  description = "Environment project the list applies to."
  type        = string
}

variable "org_id" {
  description = "Organization whose identities the project admits, CI among them."
  type        = string
}

variable "group" {
  description = "The developer group, as an IAM member string."
  type        = string
}

variable "administrator" {
  description = "The administrator from org/gcp/_setup, as an IAM member string."
  type        = string
}

variable "members" {
  description = "Handle to each person's Google account and their profiles on this project."
  type = map(object({
    account  = string
    profiles = list(string)
  }))
  sensitive = true
}

variable "lift_domain_rule" {
  description = "Whether the organization sets iam.allowedPolicyMemberDomains, which this project then has to lift."
  type        = bool
  default     = false
}
