# ==========================================
# 1. IAM Roles & Instance Profile
# ==========================================

# ==========================================
# ASG EC2 Security Group
# ==========================================

resource "aws_security_group" "asg_sg" {
  name        = "${local.tag_header}asg-sg"
  description = "Security Group for ASG EC2 instances"
  vpc_id      = module.network.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.tag_header}asg-sg"
  }
}

# (1) EC2 Instance Role (ASG Nodes)
resource "aws_iam_role" "asg_node_role" {
  name = "${local.tag_header}AmazonASGNodeEC2-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_read" {
  role       = aws_iam_role.asg_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "s3_read" {
  role       = aws_iam_role.asg_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.asg_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "asg_node_profile" {
  name = "${local.tag_header}ASG-Node-EC2-Instance-Profile"
  role = aws_iam_role.asg_node_role.name
}

# (2) CodeDeploy Service Role
resource "aws_iam_role" "codedeploy_role" {
  name = "${local.tag_header}AmazonCodeDeployService-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codedeploy.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "codedeploy_policy" {
  role       = aws_iam_role.codedeploy_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
}


# ==========================================
# 2. Launch Template & UserData
# ==========================================

# Amazon Linux 2023 최신 AMI 조회
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}


resource "aws_launch_template" "asg_lt" {
  name_prefix   = "${local.tag_header}asg-launch-template-"
  image_id      = data.aws_ami.al2023.id
  instance_type = "t3.micro"

  # =====================================================
  # TODO:
  # 아래 SG ID는 강사님 환경 값이 아니라
  # 현재 std16-ex8 VPC 안의 Security Group으로 바꿔야 함
  # =====================================================
  vpc_security_group_ids = [
    aws_security_group.asg_sg.id
  ]

  iam_instance_profile {
    name = aws_iam_instance_profile.asg_node_profile.name
  }

  # Docker 및 CodeDeploy Agent 자동 설치 스크립트
  # Terraform이 base64 자동 인코딩
  user_data = base64encode(<<-EOF
              #!/bin/bash

              dnf update -y
              dnf install -y ruby wget docker

              systemctl start docker
              systemctl enable docker
              usermod -aG docker ec2-user

              cd /tmp

              wget https://aws-codedeploy-us-east-2.s3.us-east-2.amazonaws.com/latest/install

              chmod +x ./install
              ./install auto

              systemctl start codedeploy-agent
              systemctl enable codedeploy-agent
              EOF
  )

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "${local.tag_header}asg-node-instance"
    }
  }
}


# ==========================================
# 3. Auto Scaling Group
# ==========================================

# 타겟 서브넷 조회
# Type=cluster 태그가 붙은 Subnet 조회
data "aws_subnets" "target_subnets" {
  filter {
    name   = "tag:Type"
    values = ["cluster"]
  }

  filter {
    name   = "vpc-id"
    values = [module.network.vpc_id]
  }

  depends_on = [module.network]
}


resource "aws_autoscaling_group" "asg" {
  name             = "${local.tag_header}codedeploy-asg"
  min_size         = 1
  max_size         = 3
  desired_capacity = 2

  vpc_zone_identifier = data.aws_subnets.target_subnets.ids

  launch_template {
    id      = aws_launch_template.asg_lt.id
    version = "$Latest"
  }
}


# ==========================================
# 4. CodeDeploy Application & Deployment Group
# ==========================================

# CodeDeploy Application 생성
resource "aws_codedeploy_app" "app" {
  compute_platform = "Server"
  name             = "${local.tag_header}asg-codedeploy-app"
}


# CodeDeploy Deployment Group 생성 (ASG 연동)
resource "aws_codedeploy_deployment_group" "dg" {
  app_name              = aws_codedeploy_app.app.name
  deployment_group_name = "${local.tag_header}asg-deployment-group"
  service_role_arn      = aws_iam_role.codedeploy_role.arn

  autoscaling_groups = [
    aws_autoscaling_group.asg.name
  ]

  deployment_config_name = "CodeDeployDefault.AllAtOnce"
}

# ======================================================================
# 5. CodePipeline 서비스 IAM Role
# ======================================================================

resource "aws_iam_role" "codepipeline_role" {
  name = "${local.tag_header}AmazonCodePipelineService-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "${local.tag_header}CodePipelineServicePolicy"
  role = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketVersioning",
          "s3:PutObjectAcl",
          "s3:PutObject"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "codedeploy:CreateDeployment",
          "codedeploy:GetApplication",
          "codedeploy:GetApplicationRevision",
          "codedeploy:GetDeployment",
          "codedeploy:GetDeploymentConfig",
          "codedeploy:RegisterApplicationRevision"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "codeconnections:UseConnection",
          "codestar-connections:UseConnection"
        ]
        Resource = aws_codestarconnections_connection.github.arn
      }
    ]
  })
}


# ======================================================================
# 6. Pipeline Artifacts 저장용 S3 Bucket
# ======================================================================

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "pipeline_bucket" {
  bucket        = "${local.tag_header}pipeline-artifacts-${random_id.bucket_suffix.hex}"
  force_destroy = true
}


# ======================================================================
# AWS - GitHub 간 Connection
# ======================================================================

resource "aws_codestarconnections_connection" "github" {
  name          = "${local.tag_header}github-connection"
  provider_type = "GitHub"
}


# ======================================================================
# 7. AWS CodePipeline 생성
# ======================================================================

resource "aws_codepipeline" "codepipeline" {
  name     = "${local.tag_header}asg-cicd-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.pipeline_bucket.bucket
    type     = "S3"
  }

  # Stage 1: Source
  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github.arn
        FullRepositoryId = "rladmswlr/ex8-tot"
        BranchName       = "main"
      }
    }
  }

  # Stage 2: Deploy
  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeploy"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ApplicationName     = aws_codedeploy_app.app.name
        DeploymentGroupName = aws_codedeploy_deployment_group.dg.deployment_group_name
      }
    }
  }
}
