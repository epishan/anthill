terraform {
  backend "s3" {}
}

module "backend" {
  source     = "./modules/backend"
  s3_tfstate = var.s3_tfstate
}
