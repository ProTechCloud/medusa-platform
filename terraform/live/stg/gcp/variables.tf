variable "project_id" { type = string }

variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "environment" {
  type    = string
  default = "stg"
}

variable "management_state_bucket" {
  description = "Where the _setup roots keep their state. Read-only from here."
  type        = string
}

variable "app_port" {
  description = "Loopback port the application listens on."
  type        = number
  default     = 8080
}
