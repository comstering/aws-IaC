terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.61"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14.0"
    }
  }

  required_version = ">= 1.9.2"
}

provider "aws" {
  region = "ap-northeast-2"

  default_tags {
    tags = {
      MakeBy = "terraform"
    }
  }
}

module "vpc" {
  source = "./vpc"
  name = {
    vpc                           = "hansu-vpc"
    public_subnet                 = "public"
    eks_control_plane_subnet      = "eks-private"
    private_subnet                = "private"
    db_private_subnet             = "db-private"
    eks_control_plane_route_table = "eks-control-plane-rtb"
    public_route_table            = "public-rtb"
    private_route_table           = "private-rtb"
    db_route_table                = "db-rtb"
    internet_gateway              = "igw"
    public_nat_gateway            = "nat-public-gw"
  }
  cidr                    = "10.0.0.0/16"
  availability_zone_count = 3
  subnet_cidr = {
    public            = ["10.0.0.0/27", "10.0.0.32/27", "10.0.0.64/27"]
    eks_control_plane = ["10.0.0.192/28", "10.0.0.208/28", "10.0.0.224/28"]
    private           = ["10.0.16.0/20", "10.0.32.0/20", "10.0.48.0/20"]
    db_private        = ["10.0.244.0/22", "10.0.248.0/22", "10.0.252.0/22"]
  }
}

module "security_group" {
  source = "./security-group"

  vpc = {
    id   = module.vpc.vpc_id
    name = module.vpc.vpc_name
  }
}

module "eks" {
  source = "./eks"

  name = {
    eks = "hansu-eks"
  }

  subnet_ids = {
    control_plane = module.vpc.subnet_ids.eks_control_plane
    node          = module.vpc.subnet_ids.private_subnets
  }
}

module "rds" {
  source = "./rds/aurora-mysql"

  name = {
    db_cluster = "hansu-aurora-rds"
    db         = "hansu"
  }

  vpc = {
    db_subnet_ids   = module.vpc.subnet_ids.db_private_subnets
    db_subnet_group = module.vpc.subnet_groups.db
    security_groups = [module.security_group.sg_id.mysql]
  }
}

module "msk" {
  source = "./msk"

  name = {
    msk            = "hansu-msk"
    security_group = "hansu-msk-sg"
  }

  vpc = {
    security_groups = [module.security_group.sg_id.msk]
    subnet_ids      = module.vpc.subnet_ids.private_subnets
  }
}

module "kafka_system_storage_gateway" {
  source = "./kafka-system-storage-gateway"

  name = {
    s3               = "kafka-system-storage"
    gateway          = "kafka-system-storage-gateway"
    gateway_instance = "kafka-system-storage-gateway"
    iam_role         = "StorageGatewayBucketAccessRole"
  }

  vpc = {
    id                               = module.vpc.vpc_id
    subnet_ids                       = module.vpc.subnet_ids.public_subnets
    gateway_instance_subnet          = module.vpc.subnet_ids.public_subnets[0]
    gateway_instance_security_groups = [module.security_group.sg_id.s3_storage_gateway]
    gateway_endpoint_security_groups = [module.security_group.sg_id.storage_gateway_endpoint]
  }
}

module "iam" {
  source = "./msa-iam"

  eks = {
    name     = module.eks.eks_info.name
    arn      = module.eks.eks_info.arn
    oidc_arn = module.eks.eks_info.oidc_arn
    oidc_url = module.eks.eks_info.oidc_url
  }
}
