variable "account_id" {
  description = "Cloudflare account that owns the tunnel."
  type        = string
}

variable "zone_id" {
  description = "Cloudflare zone the DNS record is published in."
  type        = string
}

variable "domain" {
  description = "Zone apex, e.g. `example.site`."
  type        = string
}

variable "environment" {
  type    = string
  default = "stg"
}

variable "environment_state_bucket" {
  description = "Bucket holding the environment's workload state, read to learn which port the tunnel must route to."
  type        = string
}
