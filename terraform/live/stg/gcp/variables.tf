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

variable "spoke_service_account" {
  description = "Spoke this run acts as. The plan workflow passes the read-only spoke, the apply workflow the write one, so the same root is harmless or not depending only on which identity CI hands it."
  type        = string
}

variable "domain" {
  description = "Zone the API is published under, the same value the Cloudflare roots take. The uptime check is built from it, so it calls the address a user calls rather than the instance."
  type        = string
}
