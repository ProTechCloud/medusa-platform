# What the Cloudflare root needs from here, as one object under that root's
# prefix in the management bucket: the address the hostname resolves to and, per
# hostname, the CNAME that proves it to Certificate Manager. One object, so the
# Cloudflare root never sees one value without the other.
#
# `published_hosts` names the hostnames whose A record the Cloudflare root
# publishes. Each joins once it serves TLS and stays, so a renewal that shows
# its certificate as provisioning again never takes its record down.
#
# The object is named by its content and the new one is written before the old
# one is deleted: there is always a handoff, and a changed content is always a
# new object, never an update the provider cannot plan.
locals {
  handoff_prefix = "${module.shared.environment}/cloudflare/handoff/"
  hosts          = keys(module.load_balancer.dns_authorization_records)
}

data "google_storage_bucket_objects" "previous_handoff" {
  bucket = var.management_state_bucket
  prefix = "${local.handoff_prefix}gcp"
}

# One normally, two after an apply that wrote the new one and failed before
# deleting the old.
data "google_storage_bucket_object_content" "previous_handoff" {
  for_each = toset([
    for object in data.google_storage_bucket_objects.previous_handoff.bucket_objects : object.name
    if can(regex("^${local.handoff_prefix}gcp-[0-9a-f]{16}\\.json$", object.name))
  ])

  bucket = var.management_state_bucket
  name   = each.value
}

locals {
  previously_published = flatten([
    for object in data.google_storage_bucket_object_content.previous_handoff :
    jsondecode(object.content).published_hosts
  ])
  published_hosts = sort(distinct(concat(
    [for host in local.previously_published : host if contains(local.hosts, host)],
    module.load_balancer.serving_hosts,
  )))

  handoff_content = jsonencode({
    load_balancer_ip               = module.load_balancer.ip_address
    certificate_dns_authorizations = module.load_balancer.dns_authorization_records
    published_hosts                = local.published_hosts
  })
}

resource "google_storage_bucket_object" "cloudflare_handoff" {
  bucket       = var.management_state_bucket
  name         = "${local.handoff_prefix}gcp-${substr(sha256(local.handoff_content), 0, 16)}.json"
  content_type = "application/json"
  content      = local.handoff_content

  lifecycle {
    create_before_destroy = true
  }
}
