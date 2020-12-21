provider "aws" {
  version = "~> 2.31.0"
  region  = var.region
}

module "aws_key_pair" {
  source              = "git::https://github.com/cloudposse/terraform-aws-key-pair.git?ref=tags/0.13.1"
  namespace           = module.this.namespace
  stage               = module.this.stage
  name                = module.this.name
  attributes          = module.this.attributes
  ssh_public_key_path = var.ssh_public_key_path
  generate_ssh_key    = true
}

module "vpc" {
  source = "git::https://github.com/cloudposse/terraform-aws-vpc.git?ref=tags/0.17.0"

  cidr_block = var.cidr_block

  context = module.this.context
}

module "ec2_instance" {
  source = "git::https://github.com/cloudposse/terraform-aws-ec2-instance.git?ref=tags/0.25.0"

  ssh_key_pair                = module.aws_key_pair.key_name
  vpc_id                      = module.vpc.vpc_id
  subnet                      = module.subnets.public_subnet_ids[0]
  security_groups             = [module.vpc.vpc_default_security_group_id]
  assign_eip_address          = var.assign_eip_address
  associate_public_ip_address = var.associate_public_ip_address
  instance_type               = var.instance_type
  allowed_ports               = var.allowed_ports
  allowed_ports_udp           = var.allowed_ports_udp
  instance_profile            = aws_iam_instance_profile.test.name

  context = module.this.context
  tags = {
    Service = "vault"
  }
}

module "kms_vault_unseal" {
  source = "git::https://github.com/cloudposse/terraform-aws-kms-key.git?ref=tags/0.7.0"

  description             = "Vault unseal key"
  deletion_window_in_days = 7
  enable_key_rotation     = false
  alias                   = "alias/vault_unseal"

  context = module.this.context
}

module "subnets" {
  source = "git::https://github.com/cloudposse/terraform-aws-dynamic-subnets.git?ref=tags/0.28.0"

  availability_zones   = var.availability_zones
  vpc_id               = module.vpc.vpc_id
  igw_id               = module.vpc.igw_id
  cidr_block           = module.vpc.vpc_cidr_block
  nat_gateway_enabled  = false
  nat_instance_enabled = false

  context = module.this.context
}

module "instance_profile_label" {
  source = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.19.2"

  attributes = distinct(compact(concat(module.this.attributes, ["profile"])))

  context = module.this.context
}

resource "aws_iam_role" "test" {
  name               = module.instance_profile_label.id
  assume_role_policy = data.aws_iam_policy_document.test-assume.json
  tags               = module.instance_profile_label.tags
}

resource "aws_iam_role_policy_attachment" "instance-role-policy-attachment" {
  role       = module.instance_profile_label.id
  policy_arn = aws_iam_policy.instance-policy.arn
}

resource "aws_iam_policy" "instance-policy" {
  name   = module.instance_profile_label.id
  policy = data.aws_iam_policy_document.test-policy.json
}

data "aws_iam_policy_document" "test-policy" {
  statement {
    actions = [
      "kms:Encrypt",
      "kms:DescribeKey",
      "kms:Decrypt"
    ]
    resources = [module.kms_vault_unseal.key_arn]
  }
}

data "aws_iam_policy_document" "test-assume" {
  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRole"
    ]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}


# https://github.com/hashicorp/terraform-guides/tree/master/infrastructure-as-code/terraform-0.13-examples/module-depends-on
resource "aws_iam_instance_profile" "test" {
  name = module.instance_profile_label.id
  role = aws_iam_role.test.name
}
