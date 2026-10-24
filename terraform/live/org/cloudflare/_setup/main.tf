# The two long-lived Cloudflare tokens, created here rather than clicked in a
# dashboard.
#
# Account-owned, not user-owned. `cloudflare_account_token` and
# `/accounts/{id}/tokens` belong to the Cloudflare account; `cloudflare_api_token`
# and `/user/tokens` belong to a person, and a person leaving takes CI with
# them. Account tokens are also what Cloudflare documents for automation.
#
# That choice is also what makes the mint token expressible here at all. The
# user API refuses to let one token create another that manages tokens —
# `{"code":1001,"message":"sub-token is not allowed to have permissions to
# manage other tokens"}` — because every user token is a sub-token of a person.
# An account token managing account tokens is not that relationship.
#
# This is the one root that belongs in `_setup` on the Cloudflare side: CI
# cannot run at all without these, and a person applies it holding a bootstrap
# account token whose only permission is `Account API Tokens Write`.
#
# The point is not that a hand-made secret is untidy. It is that a token's
# policy is the security boundary, and a policy clicked in a dashboard is
# reviewed by nobody. Everything else in this repository makes permission
# readable in a diff.
#
# Both values land in this root's state. `org/cloudflare/setup` lives in the
# management bucket, and the IAM condition in org/gcp/_setup limits the
# Cloudflare CI identities to `org/cloudflare/live/`, so only the bootstrap
# admin can read this prefix. The README lists both as secrets that reach
# state, as the standard asks.

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
    tokens_write  = { name = "Account API Tokens Write", scope = "com.cloudflare.api.account" }
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
data "cloudflare_account_api_token_permission_groups_list" "lookup" {
  for_each = local.permission_groups

  account_id = var.account_id
  name       = each.value.name
  scope      = each.value.scope
}

locals {
  group_id = {
    for key, wanted in local.permission_groups :
    key => one([
      for group in data.cloudflare_account_api_token_permission_groups_list.lookup[key].result :
      group.id if group.name == wanted.name
    ])
  }
}

# ---------- the plan token ----------
# Read-only, and a repository secret rather than an environment one: plans run
# on pull-request code, and `uses: ./…` resolves from the pull request's own
# branch, so any secret a plan job holds is reachable by a workflow an
# unreviewed branch can rewrite. The worst a leak buys here is reading records
# that are already public.
#
# The read groups mirror the write groups the apply job mints for itself, so
# the two stay comparable when either changes.
resource "cloudflare_account_token" "plan" {
  account_id = var.account_id
  name       = "medusa-cloudflare-plan"

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

# ---------- the mint token ----------
# Held as an environment secret on stg, prd and cloudflare-org, usable only
# from dev, because it is what the apply jobs use to create their per-job write
# tokens through `/accounts/{id}/tokens`.
#
# `Account API Tokens Write` and nothing else, which narrows what it does
# directly and not what it can reach: a token that can mint can mint one with
# any permission the account holds. It is a master key with a narrow surface,
# not a low-privilege credential, and rotating it is the lever to pull if
# anything in CI leaks.
resource "cloudflare_account_token" "mint" {
  account_id = var.account_id
  name       = "medusa-cloudflare-mint"

  policies = [{
    effect            = "allow"
    permission_groups = [{ id = local.group_id.tokens_write }]
    resources         = jsonencode({ "com.cloudflare.api.account.${var.account_id}" = "*" })
  }]
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
