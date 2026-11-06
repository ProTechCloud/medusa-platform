locals {
  setup = data.terraform_remote_state.setup.outputs
  name  = "medusa-${var.environment}"

  # Base labels. `component` is added at each module call, because the point
  # of the label is to tell the parts apart in billing and in an audit — one
  # value shared by every resource would not.
  labels = {
    env          = var.environment
    "managed-by" = "terraform"
  }
}
