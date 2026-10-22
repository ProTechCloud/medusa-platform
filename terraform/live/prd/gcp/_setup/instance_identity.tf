# The identity the VM runs as is created here, not in the workload root.
#
# It was in the workload root, which forced the apply spoke to hold
# serviceAccountAdmin. That role cannot be narrowed: IAM conditions can only
# read resource.name for services that publish it, and iam.googleapis.com does
# not. A condition naming medusa-${var.environment}-vm therefore evaluates
# false and grants nothing, while an unconditioned grant would let the apply
# identity edit every service account in the project, its own spokes included.
#
# Creating it alongside the spokes removes the dilemma: the apply identity
# never needs to create a service account, so it never needs the role.
resource "google_service_account" "instance" {
  account_id   = "medusa-${var.environment}-vm"
  project      = var.project_id
  display_name = "medusa ${var.environment} instance"
  description  = "Runs the API container and the tunnel connector."
}

# Attaching an identity to a VM is a permission on the identity, not on the
# VM. Without this the apply fails at instance creation with a message about
# the service account rather than about the instance.
resource "google_service_account_iam_member" "apply_attaches_instance" {
  service_account_id = google_service_account.instance.name
  role               = "roles/iam.serviceAccountUser"
  member             = module.apply_spoke.member
}

# The developers need the same thing, on the same one account. OS Login checks
# iam.serviceAccounts.actAs on every connection, so without this the IAP
# tunnel opens and the shell is still refused — a failure that reads like the
# tunnel is broken rather than like a missing grant on the VM's identity.
#
# This is what makes server-access the higher-trust of the two developer
# roles. A shell on the box is the box's identity: the metadata server hands
# out a token for this account, and this account reads the tunnel-token secret
# because it needs it at boot. The deny policy on the group does not reach
# that path — it names the person, and the caller is the VM. Removing this
# grant would not close it either, since a shell can read the token out of the
# running connector. It is documented in the README rather than pretended
# away.
resource "google_service_account_iam_member" "developers_act_as_instance" {
  service_account_id = google_service_account.instance.name
  role               = "roles/iam.serviceAccountUser"
  member             = local.developer_group
}
