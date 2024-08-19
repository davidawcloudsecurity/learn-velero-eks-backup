provider "aws" {
  region = var.region
}

variable "bucket_name" {
  description = "The name of the S3 bucket to be created"
  type        = string
}

variable "primary_cluster" {
  description = "The name of the primary EKS cluster"
  type        = string
}

variable "recovery_cluster" {
  description = "The name of the recovery EKS cluster"
  type        = string
}

# S3 Bucket
resource "aws_s3_bucket" "velero" {
  bucket = var.bucket_name
  acl    = "private"

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
resource "aws_iam_role" "velero_primary_role" {
  name = "eks-velero-backup"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "eks.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })

  managed_policy_arns = [
    aws_iam_policy.velero_policy.arn
  ]
}

# IAM Role for Velero in Recovery Cluster
resource "aws_iam_role" "velero_recovery_role" {
  name = "eks-velero-recovery"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "eks.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })

  managed_policy_arns = [
    aws_iam_policy.velero_policy.arn
  ]
}

# EKS IAM Service Account for Velero in Primary Cluster
resource "aws_eks_identity_provider_config" "primary_iam_service_account" {
  cluster_name = var.primary_cluster
  service_name = "eks.amazonaws.com"

  iam_roles = [
    aws_iam_role.velero_primary_role.arn
  ]
}

# EKS IAM Service Account for Velero in Recovery Cluster
resource "aws_eks_identity_provider_config" "recovery_iam_service_account" {
  cluster_name = var.recovery_cluster
  service_name = "eks.amazonaws.com"

  iam_roles = [
    aws_iam_role.velero_recovery_role.arn
  ]
}

# Outputs
output "s3_bucket_name" {
  value = aws_s3_bucket.velero.bucket
}

output "velero_policy_arn" {
  value = aws_iam_policy.velero_policy.arn
}

output "primary_iam_role_arn" {
  value = aws_iam_role.velero_primary_role.arn
}

output "recovery_iam_role_arn" {
  value = aws_iam_role.velero_recovery_role.arn
}
