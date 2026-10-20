variable "zone_id" {
  description = "The shared zone."
  type        = string
}

variable "records" {
  description = <<-EOT
    DNS records that belong to no environment — an apex record, a verification
    TXT, a mail route. Environment hostnames are not declared here: they are
    created by that environment's own Cloudflare root, so a change to stg's
    hostname cannot be applied by the org pipeline.

    Empty by default. The root exists so org-wide records have one obvious
    home; inventing records to fill it would be worse than leaving it empty.
  EOT
  type = map(object({
    type    = string
    content = string
    proxied = optional(bool, false)
    ttl     = optional(number, 1)
    comment = optional(string, "managed by terraform")
  }))
  default = {}
}
