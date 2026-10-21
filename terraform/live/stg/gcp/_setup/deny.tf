# Deny beats allow everywhere, including a role someone grants by hand later
# in the console. These are the guarantees that survive a mistake, as opposed
# to the role lists above, which only describe the intent.

locals {
  deny_parent = urlencode("cloudresourcemanager.googleapis.com/projects/${var.project_id}")

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

  # There is no rule here forbidding the apply identity from editing the
  # spokes. Deny conditions accept only tag-matching functions — endsWith and
  # extract are both rejected — so the restriction cannot be written as a
  # deny. It lives in the allow instead: serviceAccountAdmin reaches only the
  # instance account, so the spokes are out of reach to begin with.

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
