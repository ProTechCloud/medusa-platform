variable "project_id" {
  description = "Environment project the developers get access to."
  type        = string
}

variable "project_number" {
  description = "Project number. Deny policies address the project by number-free URL but need the id; the number is used for the attachment point."
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

variable "server_access_instance" {
  description = "Name of the one VM the server-access role may tunnel to. Scoping the grant to a single instance means a second VM added later is not reachable by default."
  type        = string
}

variable "zone" {
  description = "Zone of that VM, needed to build the condition's resource name."
  type        = string
}
