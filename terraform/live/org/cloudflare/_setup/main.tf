# The zone settings moved to org/cloudflare, so they go through plan, review
# and apply like every other change. A _setup root holds only what CI needs in
# order to run at all, and CI does not need these to run — it needs them to be
# reviewed.
#
# `removed` with `destroy = false` rather than deleting the resource block:
# deleting it would make Terraform destroy the settings, and destroying a
# cloudflare_zone_setting does not remove anything, it resets that setting to
# Cloudflare's default. `ssl` would drop from strict to flexible on a live
# zone, between this apply and the next one.
#
# This block forgets them instead. The values stay exactly as they are at the
# edge, unmanaged for the window between this apply and the merge that lets
# org/cloudflare take them over.
removed {
  from = cloudflare_zone_setting.this

  lifecycle {
    destroy = false
  }
}
