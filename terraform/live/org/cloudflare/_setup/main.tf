# strict, not full: `full` accepts any certificate at the origin including a
# self-signed one, which means the edge-to-origin leg can be intercepted
# without anything failing visibly.
resource "cloudflare_zone_setting" "this" {
  for_each = var.zone_settings

  zone_id    = var.zone_id
  setting_id = each.key
  value      = each.value
}
