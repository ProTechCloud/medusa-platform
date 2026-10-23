# The two long-lived Cloudflare tokens, created here rather than clicked in a
# dashboard.
#
# This is the one root that belongs in `_setup` on the Cloudflare side: CI
# cannot run at all without these, and they are applied by a person holding a
# bootstrap token whose only permission is `API Tokens Write` — Cloudflare's
# own "Create Additional Tokens" template, which their documentation says
# should carry no other permission.
#
# The point is not that a hand-made secret is untidy. It is that a token's
# policy is the security boundary, and a policy clicked in a dashboard is
# reviewed by nobody. Everything else in this repository makes permission
# readable in a diff; without this, the Cloudflare side was the exception.
#
# Both token values land in this root's state, which is why the state matters:
# `org/cloudflare/setup` lives in the management bucket, and the IAM condition
# in org/gcp/_setup limits the Cloudflare CI identities to
# `org/cloudflare/live/`. Only the bootstrap admin can read this prefix. The
# README lists both tokens as secrets that reach state, as the standard asks.

# The mint token's policy has to name the user it manages tokens for, and this
# is the only call that returns that id.
#
# It needs `User Details Read` on the bootstrap token, on top of
# `API Tokens Write`. Without it this fails with a 403 and error 9109,
# "Unauthorized to access requested resource", which reads like the token is
# wrong rather than like one permission is missing.
#
# That second permission does not weaken the recommendation to keep this token
# narrow. Cloudflare's warning is about the minting power — a token that can
# mint "can create tokens with access to any of a user's resources" — so what
# must stay off it is resource permission like DNS or Zone write. Reading the
# profile of the user it already acts as adds no reach at all.
#
# Account-owned tokens would avoid this, since they are scoped to an account
# rather than a person. The provider has no resource for them at v5.
data "cloudflare_user" "this" {}

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
    tokens_write  = { name = "API Tokens Write", scope = "com.cloudflare.api.user" }
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

# ---------- the plan token ----------
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

# ---------- the mint token ----------
# Held as an environment secret on stg, prd and cloudflare-org, usable only
# from dev, because it is what the apply jobs use to create their per-job write
# tokens.
#
# It carries `API Tokens Write` and nothing else, which narrows what it does
# directly and not what it can reach: Cloudflare's documentation is explicit
# that such a token "can create tokens with access to any of a user's
# resources". It is a master key with a narrow surface, not a low-privilege
# credential, and rotating it is the lever to pull if anything in CI leaks.
#
# Scoped to the user rather than the account: the right to manage tokens is a
# right over the user's own tokens.
resource "cloudflare_api_token" "mint" {
  name = "medusa-cloudflare-mint"

  policies = [{
    effect            = "allow"
    permission_groups = [{ id = local.group_id.tokens_write }]
    resources         = jsonencode({ "com.cloudflare.api.user.${data.cloudflare_user.this.id}" = "*" })
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
