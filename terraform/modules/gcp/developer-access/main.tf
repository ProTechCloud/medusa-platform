# Human access to an environment project, in two shapes: a group that may look
# and one person who may act. Nobody gets a shell on the VM — reaching the box
# means reaching the box's identity, which reads a secret, so the two roles
# below are the whole of what a person may do here.

# ---------- role 1: read-only ----------
# `viewer` is the broad "see everything" role. It deliberately does not grant
# secretmanager.versions.access, but it does grant enough adjacent permissions
# that relying on that absence is a bet on Google never widening the role. The
# deny policy below turns it into a guarantee.
resource "google_project_iam_member" "read_only" {
  project = var.project_id
  role    = "roles/viewer"
  member  = var.group
}

# Deny beats allow, always and everywhere. Even if someone later grants this
# group secretAccessor by hand, reading a value stays refused until this
# policy is edited — and editing it shows up as a diff here.
resource "google_iam_deny_policy" "no_secret_values" {
  parent       = urlencode("cloudresourcemanager.googleapis.com/projects/${var.project_id}")
  name         = "medusa-developers-no-secret-values"
  display_name = "Developers may see that a secret exists, never its value"

  rules {
    deny_rule {
      denied_principals = [replace(var.group, "group:", "principalSet://goog/group/")]
      denied_permissions = [
        "secretmanager.googleapis.com/versions.access",
      ]
    }
  }
}

# ---------- role 2: administration ----------
# One named person, not a group, and deliberately not behind the deny above.
# Every change made outside CI therefore has exactly one owner, which is the
# point: an incident asks "who did this", and the answer cannot be "somebody in
# a group".
#
# owner rather than something narrower, because this role exists for the cases
# nobody listed in advance — a stuck lock, a half-applied change, a resource CI
# cannot reach. A narrower role would be a list of guesses that runs out
# exactly when it is needed.
resource "google_project_iam_member" "administration" {
  project = var.project_id
  role    = "roles/owner"
  member  = var.administrator
}
