provider "aws" {
  region = var.region
}

variable "region" {
  default = "ap-southeast-1"
}

variable "eks_role" {
  type = string
}

variable "aws_load_balancer_role" {
  type = string
}

data "aws_iam_role" "aws_load_balancer_role" {
  name = var.aws_load_balancer_role
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

variable "eks-velero-recovery" {
  description = "The name of the eks velero backup role to be created"
  type        = string
  default     = "eks-velero-recovery"
}

variable "primary_cluster" {
  description = "The name of the primary EKS cluster"
  type        = string
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
resource "aws_iam_role" "velero-backup" {

  name = var.eks-velero-backup
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Federated = "arn:aws:iam::${var.account_id}:oidc-provider/${local.oidc_provider_url_primary}"
        },
        Action = "sts:AssumeRoleWithWebIdentity",
        Condition = {
          StringEquals = {
            "${local.oidc_provider_url_primary}:aud" = "sts.amazonaws.com",
            "${local.oidc_provider_url_primary}:sub" = "system:serviceaccount:velero:velero-server"
          }
        }
      }
    ]
  })
  managed_policy_arns = [
    aws_iam_policy.velero_policy.arn
  ]
}

resource "aws_iam_role" "velero-recovery" {

  name = var.eks-velero-recovery
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Federated = "arn:aws:iam::${var.account_id}:oidc-provider/${local.oidc_provider_url_recovery}"
        },
        Action = "sts:AssumeRoleWithWebIdentity",
        Condition = {
          StringEquals = {
            "${local.oidc_provider_url_recovery}:aud" = "sts.amazonaws.com",
            "${local.oidc_provider_url_recovery}:sub" = "system:serviceaccount:velero:velero-server"
          }
        }
      }
    ]
  })
  managed_policy_arns = [
    aws_iam_policy.velero_policy.arn
  ]
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
}

variable "vpcid" {
  type = string
}

data "aws_vpc" "vpc" {
  id = var.vpcid
}

variable "subnet_1" {

}
data "aws_subnet" "subnet_1" {
  id = var.subnet_1
}

variable "subnet_2" {

}

data "aws_subnet" "subnet_2" {
  id = var.subnet_2
}

variable "eks_sg" {
}

data "aws_security_group" "eks_sg" {
  id = var.eks_sg
}

variable "recovery_eks_cluster" {
}
# EKS Cluster
resource "aws_eks_cluster" "recovery_eks_cluster" {
  name = var.recovery_eks_cluster
  version = var.cluster_version
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

/* remove because it generates byitself
resource "aws_eks_addon" "example" {
  cluster_name                = aws_eks_cluster.recovery_eks_cluster.name
  addon_name                  = "coredns"
  addon_version               = "v1.11.1-eksbuild.11"
  resolve_conflicts_on_update = "OVERWRITE"
}
*/

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
  fargate_profile_name   = "platform_service"
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

data "aws_eks_cluster" "primary" {
  name = var.primary_cluster
}

data "aws_eks_cluster" "recovery" {
  name = var.recovery_eks_cluster
  depends_on = [aws_eks_cluster.recovery_eks_cluster]
}

locals {
  oidc_provider_url_primary = replace(data.aws_eks_cluster.primary.identity[0].oidc[0].issuer, "https://", "")
  oidc_provider_url_recovery = replace(data.aws_eks_cluster.recovery.identity[0].oidc[0].issuer, "https://", "")
}

resource "null_resource" "create_oicd" {

  provisioner "local-exec" {
    command = <<EOT
      echo ${aws_eks_cluster.recovery_eks_cluster.name}
      ARCH=amd64
      PLATFORM=$(uname -s)_$ARCH
      curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
      tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
      sudo mv /tmp/eksctl /usr/local/bin
      eksctl utils associate-iam-oidc-provider --cluster ${aws_eks_cluster.recovery_eks_cluster.name} --approve
      curl -sLO "https://get.helm.sh/helm-v3.15.4-linux-amd64.tar.gz"
      tar -xzvf helm-v3.15.4-linux-amd64.tar.gz -C /tmp && rm helm-v3.15.4-linux-amd64.tar.gz
      sudo mv /tmp/linux-amd64/helm /usr/local/bin
      curl -sLO "https://github.com/vmware-tanzu/velero/releases/download/v1.14.1/velero-v1.14.1-linux-amd64.tar.gz"
      tar -xzvf velero-v1.14.1-linux-amd64.tar.gz -C /tmp && rm velero-v1.14.1-linux-amd64.tar.gz
      sudo mv /tmp/velero-v1.14.1-linux-amd64/velero /usr/local/bin
      helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
      cat <<EOF > values.yaml
configuration:
  backupStorageLocation:
  - bucket: ${var.bucket_name}
    provider: aws
  volumeSnapshotLocation:
  - config:
      region: ${var.region}
    provider: aws
initContainers:
- name: velero-plugin-for-aws
  image: velero/velero-plugin-for-aws:v1.7.1
  volumeMounts:
  - mountPath: /target
    name: plugins
credentials:
  useSecret: false
serviceAccount:
  server:
    annotations:
      eks.amazonaws.com/role-arn: "arn:aws:iam::${var.account_id}:role/eks-velero-backup"
# Add tolerations under the pod specification (server) section
pod:
  server:
    tolerations:
    - key: "eks.amazonaws.com/compute-type"
      operator: "Equal"
      value: "fargate"
      effect: "NoSchedule"      
EOF
      cat <<EOF2 > values_recovery.yaml
configuration:
  backupStorageLocation:
  - bucket: ${var.bucket_name}
    provider: aws
  volumeSnapshotLocation:
  - config:
      region: ${var.region}
    provider: aws
initContainers:
- name: velero-plugin-for-aws
  image: velero/velero-plugin-for-aws:v1.7.1
  volumeMounts:
  - mountPath: /target
    name: plugins
credentials:
  useSecret: false
serviceAccount:
  server:
    annotations:
      eks.amazonaws.com/role-arn: "arn:aws:iam::${var.account_id}:role/eks-velero-recovery"
# Add tolerations under the pod specification (server) section
pod:
  server:
    tolerations:
    - key: "eks.amazonaws.com/compute-type"
      operator: "Equal"
      value: "fargate"
      effect: "NoSchedule"      
EOF2
      aws eks update-kubeconfig --region ${var.region} --name ${var.recovery_eks_cluster}
      kubectl rollout restart deploy/coredns -n kube-system
      helm install velero vmware-tanzu/velero --create-namespace --namespace velero -f values_recovery.yaml
      aws eks update-kubeconfig --region ${var.region} --name ${var.primary_cluster}
      aws eks create-fargate-profile \
      --cluster-name ${var.primary_cluster} \
      --fargate-profile-name velero \
      --pod-execution-role-arn $(aws iam get-role --role-name ${var.fargate_role} --query Role.Arn --output text | sed 's/[", ]//g') \
      --subnets ${var.subnet_1} ${var.subnet_2} \
      --selectors namespace=velero      
      cat EKSASSUMEROLE.md; mv EKSASSUMEROLE.md EKSASSUMEROLE.sh
      chmod 700 EKSASSUMEROLE.sh
      ./EKSASSUMEROLE.sh
      helm install velero vmware-tanzu/velero --create-namespace --namespace velero -f values.yaml
    EOT
  }

  # Ensure this only runs when necessary
  triggers = {
    fargate_profile = aws_eks_fargate_profile.velero.id
  }
}
