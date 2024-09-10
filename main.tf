provider "aws" {
  region = var.region
}

variable "region" {
  default = "ap-southeast-1"
}

variable "eks_role" {
  type = string
}

variable "cluster_version" {
  default = 1.24
}

variable "account_id" {
  description = "The number of the account"
  type        = number
}

variable "bucket_name" {
  description = "The name of the S3 bucket to be created"
  type        = string
}

variable "eks-velero-backup" {
  description = "The name of the eks velero backup role to be created"
  type        = string
  default     = "eks-velero-backup"
}

variable "primary_cluster" {
  description = "The name of the primary EKS cluster"
  type        = string
}

data "aws_eks_cluster" "primary" {
  name = var.primary_cluster
}

locals {
  oidc_provider_url = replace(data.aws_eks_cluster.primary.identity[0].oidc[0].issuer, "https://", "")
}

# S3 Bucket
resource "aws_s3_bucket" "velero" {
  bucket = var.bucket_name

  tags = {
    Name = "Velero Backup Bucket"
  }
}

# IAM Policy for Velero
resource "aws_iam_policy" "velero_policy" {
  name        = "VeleroAccessPolicy"
  description = "Policy to allow Velero to perform backup and recovery operations"
  policy      = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:CreateSnapshot",
          "ec2:DeleteSnapshot"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:PutObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts"
        ],
        Resource = [
          "arn:aws:s3:::${var.bucket_name}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "s3:ListBucket"
        ],
        Resource = [
          "arn:aws:s3:::${var.bucket_name}"
        ]
      }
    ]
  })
}

# IAM Role for Velero in Primary Cluster
resource "aws_iam_role" "velero" {

  name = var.eks-velero-backup
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Federated = "arn:aws:iam::${var.account_id}:oidc-provider/${local.oidc_provider_url}"
        },
        Action = "sts:AssumeRoleWithWebIdentity",
        Condition = {
          StringEquals = {
            "${local.oidc_provider_url}:aud" = "sts.amazonaws.com",
            "${local.oidc_provider_url}:sub" = "system:serviceaccount:velero:velero-server"
          }
        }
      }
    ]
  })
}

# Data sources to get existing resources
data "aws_iam_role" "eks_role" {
  name = var.eks_role
  #  name = "eks-cluster-f92sh"
}

variable "fargate_role" {
  type = string
}

data "aws_iam_role" "fargate_role" {
  name = var.fargate_role
  #  name = "eks-fargate-system-profile-pd-g2xmdp7"
}

variable "vpcid" {
  type = string
}

data "aws_vpc" "vpc" {
  id = var.vpcid
  #  id = "vpc-0c264b217b411a08a"
}

variable "subnet_1" {

}
data "aws_subnet" "subnet_1" {
  id = var.subnet_1
  #  id = "subnet-02098f8ac2178bbea"
}

variable "subnet_2" {

}

data "aws_subnet" "subnet_2" {
  id = var.subnet_2
  #  id = "subnet-0749ab2836b8fac6e"
}

variable "eks_sg" {

}

data "aws_security_group" "eks_sg" {
  id = var.eks_sg
  #  id = "sg-08567c7350c264402"
}

variable "recovery_eks_cluster" {
}
# EKS Cluster
resource "aws_eks_cluster" "recovery_eks_cluster" {
  name = var.recovery_eks_cluster
  version = var.cluster_version
  #  name     = "f92sh02"
  role_arn = data.aws_iam_role.eks_role.arn

  vpc_config {
    subnet_ids         = [data.aws_subnet.subnet_1.id, data.aws_subnet.subnet_2.id]
    security_group_ids = [data.aws_security_group.eks_sg.id]
  }

  depends_on = [
    data.aws_iam_role.eks_role,
    data.aws_vpc.vpc,
    data.aws_subnet.subnet_1,
    data.aws_subnet.subnet_2,
    data.aws_security_group.eks_sg
  ]
}

# Fargate Profile for kube-system
resource "aws_eks_fargate_profile" "kube_system_profile" {
  cluster_name           = aws_eks_cluster.recovery_eks_cluster.name
  fargate_profile_name   = "kube-system"
  pod_execution_role_arn = data.aws_iam_role.fargate_role.arn

  selector {
    namespace = "kube-system"
  }

  subnet_ids = [data.aws_subnet.subnet_1.id, data.aws_subnet.subnet_2.id]

  depends_on = [aws_eks_cluster.recovery_eks_cluster]
}

# Fargate Profile for platform-service
resource "aws_eks_fargate_profile" "platform_service_profile" {
  cluster_name           = aws_eks_cluster.recovery_eks_cluster.name
  fargate_profile_name   = "platform-service"
  pod_execution_role_arn = data.aws_iam_role.fargate_role.arn

  selector {
    namespace = "platform-service"
  }

  subnet_ids = [data.aws_subnet.subnet_1.id, data.aws_subnet.subnet_2.id]

  depends_on = [aws_eks_cluster.recovery_eks_cluster]
}

# Fargate Profile for velero
resource "aws_eks_fargate_profile" "velero" {
  cluster_name           = aws_eks_cluster.recovery_eks_cluster.name
  fargate_profile_name   = "velero"
  pod_execution_role_arn = data.aws_iam_role.fargate_role.arn

  selector {
    namespace = "velero"
  }

  subnet_ids = [data.aws_subnet.subnet_1.id, data.aws_subnet.subnet_2.id]

  depends_on = [aws_eks_cluster.recovery_eks_cluster]
}

/*
# ConfigMap for platform-service
resource "kubernetes_config_map" "platform_service_config" {
  metadata {
    name      = "platform-service-config"
    namespace = "platform-service"
  }

  data = {
    "configKey" = "configValue"
  }

  depends_on = [aws_eks_fargate_profile.platform_service_profile]
}
*/

provider "kubernetes" {
  host                   = aws_eks_cluster.recovery_eks_cluster.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.recovery_eks_cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.auth.token

  # For EKS authentication
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.recovery_eks_cluster.name]
  }
}

data "aws_eks_cluster_auth" "auth" {
  name = aws_eks_cluster.recovery_eks_cluster.name
}

# Outputs
output "s3_bucket_name" {
  value = var.bucket_name
}

output "velero_policy_arn" {
  value = aws_iam_policy.velero_policy.arn
}

output "primary_cluster" {
  value = var.primary_cluster
}
