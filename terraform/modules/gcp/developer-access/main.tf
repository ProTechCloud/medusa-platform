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

# ---------- role 2: server-access ----------
# Granted separately so it can be given to some people and not others, and so
# revoking shell access does not also remove the ability to read dashboards.
#
# Only half of it is here. The tunnel itself is granted on the instance, by
# `google_iap_tunnel_instance_iam_member` in the workload root — the root that
# creates the VM and so can name it. Binding on the instance is what keeps a
# second VM in the same zone out of reach; a project-level grant, conditional
# or not, cannot do that from here, because this root runs before any VM
# exists.
#
# OS Login is project-level and belongs here: reaching the port is not the
# same as being let in. It makes the shell itself an IAM decision, so removing
# someone from the group closes their session path without touching any key
# file on the box.
resource "google_project_iam_member" "os_login" {
  project = var.project_id
  role    = "roles/compute.osLogin"
  member  = var.group
}
