variable "project_id" {
  description = "Environment project the developers get access to."
  type        = string
}

variable "group" {
  description = <<-EOT
    The developer group, as an IAM member string. Either a Workspace group or a
    consumer Google group — IAM accepts both, as `group:address`. Membership is
    managed in the group, not here, so adding or removing a person is not a
    code change and not a deploy.
  EOT
  type        = string

  validation {
    condition     = startswith(var.group, "group:")
    error_message = "Must be a group, written as `group:address`. Naming a person directly would make every access change a pull request."
  }
}
