# setup-cd applies this root, but the first apply and an emergency are run by a
# person with the bootstrap admin identity, so a human credential is accepted
# here. Every workload root leaves this false, which is what makes a laptop-run
# of one fail instead of quietly succeeding.
module "pin" {
  source = "../../../../modules/gcp/project-pin"

  expected_project_id    = var.management_project_id
  allow_user_credentials = true
}
