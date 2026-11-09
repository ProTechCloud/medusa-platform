# What every stg root agrees on, said once. The roots cannot read each other's
# state, so a value they share lives here, with no provider and no state of its
# own, and each root calls this module. Nothing here is secret.
module "naming" {
  source = "../../../modules/naming"

  environment = "stg"
  zone        = "medusa.fabianalula.site"
}
