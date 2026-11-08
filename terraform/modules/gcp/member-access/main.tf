# Who may use one environment project, from the list in ORG_MEMBERS_ACCESS.
# Applied on demand, behind a reviewer, because a wrong list can lock a person
# out.

module "profiles" {
  source = "../access-profiles"
}

locals {
  # Keyed by handle and role, which say nothing about who the person is. The
  # addresses stay sensitive, so they do not reach the run's log.
  grants = nonsensitive(toset(flatten([
    for handle, member in var.members : [
      for profile in member.profiles : [
        for role in module.profiles.roles[profile] : "${handle}|${role}"
      ]
    ]
  ])))

  subject = "principal://goog/subject/"
  administrators = distinct(concat(
    [replace(var.administrator, "user:", local.subject)],
    [for member in values(var.members) : "${local.subject}${member.account}" if contains(member.profiles, "administration")],
  ))
}

resource "google_project_iam_member" "profile" {
  for_each = local.grants

  project = var.project_id
  role    = split("|", each.key)[1]
  member  = "user:${var.members[split("|", each.key)[0]].account}"
}

# A person in the developer group who also administers the project has to read a
# secret during a recovery, so they are spared. Everyone else in the group stays
# refused, whatever role they are granted by hand later.
resource "google_iam_deny_policy" "no_secret_values" {
  parent       = urlencode("cloudresourcemanager.googleapis.com/projects/${var.project_id}")
  name         = "medusa-developers-no-secret-values"
  display_name = "Developers may see that a secret exists, never its value"

  rules {
    deny_rule {
      denied_principals    = [replace(var.group, "group:", "principalSet://goog/group/")]
      exception_principals = local.administrators
      denied_permissions = [
        "secretmanager.googleapis.com/versions.access",
      ]
    }
  }
}

# Refuses a role for any account not named here. The organization's principal set
# is what admits CI: the service accounts and the identity pool live inside it,
# and a binding for them would otherwise be refused too.
resource "google_org_policy_policy" "allowed_members" {
  name   = "projects/${var.project_id}/policies/iam.managed.allowedPolicyMembers"
  parent = "projects/${var.project_id}"

  spec {
    rules {
      enforce = "TRUE"
      parameters = jsonencode({
        allowedMemberSubjects = distinct(concat(
          [var.administrator, var.group],
          [for member in values(var.members) : "user:${member.account}"],
        ))
        allowedPrincipalSets = ["//cloudresourcemanager.googleapis.com/organizations/${var.org_id}"]
      })
    }
  }
}

# The domain rule refuses every account outside the organization's domain, listed
# or not. It is lifted only after the list above holds, so the project is never
# left with neither rule.
resource "google_org_policy_policy" "domain_rule_lifted" {
  count = var.lift_domain_rule ? 1 : 0

  name   = "projects/${var.project_id}/policies/iam.allowedPolicyMemberDomains"
  parent = "projects/${var.project_id}"

  spec {
    rules {
      allow_all = "TRUE"
    }
  }

  depends_on = [google_org_policy_policy.allowed_members]
}
