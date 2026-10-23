# The long-lived Cloudflare plan token, created here rather than clicked in a
# dashboard.
#
# This is the one root that belongs in `_setup` on the Cloudflare side: CI
# cannot run at all without this token, and it is applied by a person holding a
# bootstrap token whose only permission is `API Tokens Write` — Cloudflare's
# own "Create Additional Tokens" template.
#
# The point is not that a hand-made secret is untidy. It is that a token's
# policy is the security boundary, and a policy clicked in a dashboard is
# reviewed by nobody. Everything else in this repository makes permission
# readable in a diff.
#
# ---------------------------------------------------------------------------
# The mint token is NOT here, and cannot be.
# ---------------------------------------------------------------------------
# Creating it through the API fails:
#
#   POST /client/v4/user/tokens → 400
#   {"code":1001,"message":"sub-token is not allowed to have permissions to
#    manage other tokens"}
#
# Cloudflare refuses to let one token create another token that manages tokens,
# whatever the creating token holds. Only a human session can, which is why the
# dashboard offers the template and the API does not. Their documentation says
# such a token "can create tokens with access to any of a user's resources" —
# `any` turns out to exclude token management.
#
# So the mint token stays hand-made, and the README says so and states the
# policy it must carry. Its policy is the one Cloudflare permission in this
# repository that code cannot express.
#
# The plan token's value lands in this root's state. `org/cloudflare/setup`
# lives in the management bucket, and the IAM condition in org/gcp/_setup
# limits the Cloudflare CI identities to `org/cloudflare/live/`, so only the
# bootstrap admin can read this prefix. The README lists it as a secret that
# reaches state, as the standard asks.

# Permission groups are addressed by UUID, and the UUIDs are not stable to
# paste from a tutorial. They are looked up by name, and an exact-name match is
# taken from the result: the API's name filter is a search, so asking for
# "Zone Read" can also return "Zone Settings Read".
#
# `one()` is load-bearing. A name that matches nothing, or matches twice, stops
# the apply — rather than producing a token whose policy silently grants less
# than it reads as granting.
locals {
  permission_groups = {
    tunnel_read   = { name = "Cloudflare Tunnel Read", scope = "com.cloudflare.api.account" }
    zone_read     = { name = "Zone Read", scope = "com.cloudflare.api.account.zone" }
    dns_read      = { name = "DNS Read", scope = "com.cloudflare.api.account.zone" }
    settings_read = { name = "Zone Settings Read", scope = "com.cloudflare.api.account.zone" }
  }
}

# The names go in raw, despite the provider documentation saying the value must
# be URL-encoded. The provider encodes them itself, so passing urlencode()
# output double-encodes: a space becomes `+`, the `+` becomes `%2B`, and the
# API is asked for the literal string "Zone+Settings+Read".
#
# That failed silently rather than loudly — a filter it cannot match is
# ignored, the full list comes back, and the exact-name filter below picked the
# right one anyway. Correct by accident is still worth fixing: the filter is
# what keeps this from depending on a 1000-item default page size.
data "cloudflare_api_token_permission_groups_list" "lookup" {
  for_each = local.permission_groups

  name  = each.value.name
  scope = each.value.scope
}

locals {
  group_id = {
    for key, wanted in local.permission_groups :
    key => one([
      for group in data.cloudflare_api_token_permission_groups_list.lookup[key].result :
      group.id if group.name == wanted.name
    ])
  }
}

# Read-only, and a repository secret rather than an environment one: plans run
# on pull-request code, and `uses: ./…` resolves from the pull request's own
# branch, so any secret a plan job holds is reachable by a workflow an
# unreviewed branch can rewrite. The worst a leak buys here is reading records
# that are already public.
#
# The read groups mirror the write groups the apply job mints for itself, so
# the two stay comparable when either changes.
resource "cloudflare_api_token" "plan" {
  name = "medusa-cloudflare-plan"

  policies = [
    {
      effect            = "allow"
      permission_groups = [{ id = local.group_id.tunnel_read }]
      resources         = jsonencode({ "com.cloudflare.api.account.${var.account_id}" = "*" })
    },
    {
      effect = "allow"
      permission_groups = [
        { id = local.group_id.zone_read },
        { id = local.group_id.dns_read },
        { id = local.group_id.settings_read },
      ]
      resources = jsonencode({ "com.cloudflare.api.account.zone.${var.zone_id}" = "*" })
    },
  ]
}

# The zone settings this root used to own moved to org/cloudflare, so they go
# through plan, review and apply.
#
# `removed` with `destroy = false` rather than deleting the resource block:
# deleting it would make Terraform destroy the settings, and destroying a
# cloudflare_zone_setting does not remove anything, it resets that setting to
# Cloudflare's default. `ssl` would drop from strict to flexible on a live
# zone, between this apply and the next one.
removed {
  from = cloudflare_zone_setting.this

  lifecycle {
    destroy = false
  }
}
