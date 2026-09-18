# =========================================================
# EKS Cluster
# =========================================================
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = var.cluster_role_arn
  version  = "1.35"

  vpc_config {
    subnet_ids = var.cluster_subnet_ids

    endpoint_private_access = false
    endpoint_public_access  = true
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  tags = {
    Name = var.cluster_name
  }
}

# =========================================================
# 현재 IAM 사용자에게 EKS 접근 권한 부여
# =========================================================
resource "aws_eks_access_entry" "current_user" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.current_aws_arn

  type = "STANDARD"
}

resource "aws_eks_access_policy_association" "current_user_admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.current_aws_arn

  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [
    aws_eks_access_entry.current_user
  ]
}

# =========================================================
# EKS Managed Node Group
# =========================================================
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.project_name}-node-group"
  node_role_arn   = var.node_role_arn

  # Worker Node는 Private Subnet에 배치
  subnet_ids = var.private_subnet_ids

  instance_types = ["t3.small"]
  capacity_type  = "ON_DEMAND"
  disk_size      = 20

  scaling_config {
    desired_size = 2
    min_size     = 1
    max_size     = 3
  }

  update_config {
    max_unavailable = 1
  }

  tags = {
    Name = "${var.project_name}-node-group"
  }
}
