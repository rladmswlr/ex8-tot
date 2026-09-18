locals {
  project_name = "std16-ex8"
  cluster_name = "${local.project_name}-eks-cluster"

  tag_header = "${local.project_name}-"
}
module "network" {
  source = "./modules/network"

  project_name = local.project_name
  cluster_name = local.cluster_name
}

module "iam" {
  source = "./modules/iam"

  project_name = local.project_name
}

module "eks" {
  source = "./modules/eks"

  project_name       = local.project_name
  cluster_name       = local.cluster_name
  cluster_subnet_ids = module.network.cluster_subnet_ids
  private_subnet_ids = module.network.private_subnet_ids

  cluster_role_arn = module.iam.eks_cluster_role_arn
  node_role_arn    = module.iam.eks_node_role_arn
  current_aws_arn  = data.aws_caller_identity.current.arn

  depends_on = [
    module.iam
  ]
}
