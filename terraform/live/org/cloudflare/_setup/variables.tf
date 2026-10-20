variable "zone_id" {
  description = "The zone every environment publishes into."
  type        = string
}

variable "zone_settings" {
  description = <<-EOT
    Zone-wide security posture. These sit in a _setup root, applied by a
    person, because they are the one set of Cloudflare values that affects
    every environment at once: lowering min TLS or switching SSL mode off
    strict would weaken stg and prd together, from a single merge.
  EOT
  type        = map(string)
  default = {
    ssl                      = "strict"
    always_use_https         = "on"
    min_tls_version          = "1.2"
    automatic_https_rewrites = "on"
    opportunistic_encryption = "on"
    tls_1_3                  = "on"
    browser_check            = "on"
  }
}
