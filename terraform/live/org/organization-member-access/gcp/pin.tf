module "pin" {
  source = "../../../../modules/gcp/project-pin"

  expected_project_id    = var.management_project_id
  allow_user_credentials = true
}
