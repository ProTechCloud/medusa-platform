# What the GCP root produces for this one, read back from the handoff object it
# writes under this root's prefix (README, "Crossing roots"): the load
# balancer's address, the certificate authorization records and the published
# hosts. Before the GCP root has applied there is no object, and the records
# it feeds do not exist yet.
locals {
  handoff_prefix = "${module.shared.environment}/cloudflare/handoff/"

  # The current object, named by its content (`gcp-<hash>.json`). More than one
  # fails the plan: the GCP apply wrote a new one and has not yet deleted the
  # old, and its next apply will.
  handoff_object = one([
    for object in data.google_storage_bucket_objects.handoff.bucket_objects : object.name
    if can(regex("^${local.handoff_prefix}gcp-[0-9a-f]{16}\\.json$", object.name))
  ])
}

data "google_storage_bucket_objects" "handoff" {
  bucket = var.management_state_bucket
  prefix = "${local.handoff_prefix}gcp"
}

data "google_storage_bucket_object_content" "handoff" {
  count = local.handoff_object == null ? 0 : 1

  bucket = var.management_state_bucket
  name   = local.handoff_object

  # This root's Cloudflare token can edit the whole zone, so what it publishes
  # from the object is checked first: a bad value, from a bug or a compromised
  # GCP apply, fails the plan instead of becoming a live record.
  lifecycle {
    postcondition {
      condition     = endswith(trimsuffix(try(jsondecode(self.content).certificate_dns_authorizations[local.hostname].name, "_acme-challenge.${local.hostname}"), "."), ".${local.hostname}")
      error_message = "The handoff's certificate authorization for ${local.hostname} must be named under that hostname."
    }

    postcondition {
      condition     = can(regex("^(\\d{1,3}\\.){3}\\d{1,3}$", jsondecode(self.content).load_balancer_ip)) && can(cidrhost("${jsondecode(self.content).load_balancer_ip}/32", 0))
      error_message = "The handoff's load_balancer_ip must be an IPv4 address."
    }
  }
}

locals {
  gcp = local.handoff_object == null ? null : jsondecode(data.google_storage_bucket_object_content.handoff[0].content)
}
