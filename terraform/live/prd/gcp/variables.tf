variable "project_id" { type = string }

variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "management_state_bucket" {
  description = "Where the _setup roots keep their state. Read-only from here."
  type        = string
}

variable "spoke_service_account" {
  description = "Spoke this run acts as. The plan workflow passes the read-only spoke, the apply workflow the write one, so the same root is harmless or not depending only on which identity CI hands it."
  type        = string
}

variable "alert_email" {
  description = "Address that receives the alerts. A group, so nobody's own address is in the code; it has to let anyone post, or the mail from Monitoring is refused."
  type        = string
  default     = "medusa-platform-developers@googlegroups.com"
}

variable "api_reads_posthog_project_token" {
  description = "Whether the API reads POSTHOG_PROJECT_TOKEN. True only once the secret holds a real version: until then it holds a placeholder, and the service would start with it."
  type        = bool
  default     = false
}
