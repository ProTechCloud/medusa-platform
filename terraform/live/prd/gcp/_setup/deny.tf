# Deny beats allow everywhere, including a role someone grants by hand later
# in the console. These are the guarantees that survive a mistake, as opposed
# to the role lists above, which only describe the intent.

locals {
  deny_parent = urlencode("cloudresourcemanager.googleapis.com/projects/${var.project_id}")

  spoke_names = [
    "/serviceAccounts/${module.plan_spoke.email}",
    "/serviceAccounts/${module.apply_spoke.email}",
    "/serviceAccounts/${module.tunnel_token_writer.email}",
  ]
}

# A plan runs on pull-request code that nobody has reviewed. If it can read a
# secret value, a two-line change to the plan step prints it to a public log.
resource "google_iam_deny_policy" "plan_no_secret_values" {
  parent       = local.deny_parent
  name         = "medusa-plan-no-secret-values"
  display_name = "Plan may see that a secret exists, never its value"

  rules {
    deny_rule {
      denied_principals  = [module.plan_spoke.principal]
      denied_permissions = ["secretmanager.googleapis.com/versions.access"]
    }
  }
}

resource "google_iam_deny_policy" "apply_cannot_escalate" {
  parent       = local.deny_parent
  name         = "medusa-apply-cannot-escalate"
  display_name = "Apply cannot raise its own rights or erase the record"

  # A stolen or broken apply must not be able to widen itself. Without this,
  # serviceAccountAdmin on medusa-* accounts is enough to grant the apply
  # spoke owner on its own project, because the spoke is itself medusa-*.
  rules {
    deny_rule {
      denied_principals = [module.apply_spoke.principal]
      denied_permissions = [
        "iam.googleapis.com/serviceAccounts.setIamPolicy",
        "iam.googleapis.com/serviceAccounts.update",
        "iam.googleapis.com/serviceAccounts.delete",
        "iam.googleapis.com/serviceAccounts.disable",
      ]
      denial_condition {
        title       = "the spokes themselves"
        description = "Applies to the plan, apply and tunnel-token identities."
        expression  = join(" || ", [for n in local.spoke_names : "resource.name.endsWith('${n}')"])
      }
    }
  }

  # The state bucket is the record of what exists. An apply that can delete it
  # can make the infrastructure unaccountable while leaving it running and
  # billing.
  rules {
    deny_rule {
      denied_principals = [module.apply_spoke.principal, module.plan_spoke.principal]
      denied_permissions = [
        "storage.googleapis.com/buckets.delete",
        "storage.googleapis.com/buckets.update",
        "storage.googleapis.com/buckets.setIamPolicy",
      ]
    }
  }

  # Destroying the key destroys every state file it ever encrypted, with no
  # recovery by any means once the deletion delay passes.
  rules {
    deny_rule {
      denied_principals = [module.apply_spoke.principal, module.plan_spoke.principal]
      denied_permissions = [
        "cloudkms.googleapis.com/cryptoKeyVersions.destroy",
        "cloudkms.googleapis.com/cryptoKeys.update",
        "cloudkms.googleapis.com/cryptoKeys.setIamPolicy",
      ]
    }
  }
}
