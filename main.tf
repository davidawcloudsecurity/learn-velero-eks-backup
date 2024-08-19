provider "aws" {
  region = "ap-southeast-1"
}

# Data sources to get existing resources
data "aws_iam_role" "eks_role" {
  name = "eks-cluster-f92sh"
}

data "aws_vpc" "vpc" {
  id = "vpc-0c264b217b411a08a"
}

data "aws_subnet" "subnet_1" {
  id = "subnet-02098f8ac2178bbea"
}

data "aws_subnet" "subnet_2" {
  id = "subnet-0749ab2836b8fac6e"
}

data "aws_security_group" "eks_sg" {
  id = "sg-08567c7350c264402"
}

# EKS Cluster
resource "aws_eks_cluster" "eks_cluster" {
  name     = "f92sh02"
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
  cluster_name           = aws_eks_cluster.eks_cluster.name
  fargate_profile_name   = "kube-system"
  pod_execution_role_arn = data.aws_iam_role.eks_role.arn

  selector {
    namespace = "kube-system"
  }

  subnet_ids = [data.aws_subnet.subnet_1.id, data.aws_subnet.subnet_2.id]

  depends_on = [aws_eks_cluster.eks_cluster]
}

# Fargate Profile for platform-service
resource "aws_eks_fargate_profile" "platform_service_profile" {
  cluster_name           = aws_eks_cluster.eks_cluster.name
  fargate_profile_name   = "platform-service"
  pod_execution_role_arn = data.aws_iam_role.eks_role.arn

  selector {
    namespace = "platform-service"
  }

  subnet_ids = [data.aws_subnet.subnet_1.id, data.aws_subnet.subnet_2.id]

  depends_on = [aws_eks_cluster.eks_cluster]
}

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

provider "kubernetes" {
  host                   = aws_eks_cluster.eks_cluster.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.eks_cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.auth.token

  # For EKS authentication
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.eks_cluster.name]
  }
}

data "aws_eks_cluster_auth" "auth" {
  name = aws_eks_cluster.eks_cluster.name
}
