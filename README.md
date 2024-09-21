!#/bin/bash
# learn-velero-eks-backup
## Prerequisite
1. Install eksctl - https://eksctl.io/installation/
```bash
# for ARM systems, set ARCH to: `arm64`, `armv6` or `armv7`
ARCH=amd64
PLATFORM=$(uname -s)_$ARCH
curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
# (Optional) Verify checksum
curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_checksums.txt" | grep $PLATFORM | sha256sum --check
tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
sudo mv /tmp/eksctl /usr/local/bin
```
3. Download helm - https://github.com/helm/helm/releases
```bash
curl -sLO "https://get.helm.sh/helm-v3.15.4-linux-amd64.tar.gz"
tar -xzvf helm-v3.15.4-linux-amd64.tar.gz -C /tmp && rm helm-v3.15.4-linux-amd64.tar.gz
sudo mv /tmp/linux-amd64/helm /usr/local/bin
```
https://get.helm.sh/helm-v3.15.4-linux-amd64.tar.gz
   
4. Create an IAM OIDC provider for your cluster - https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html
```bash
cluster_name=$(aws eks list-cluster --query clusters[0] --output text); \
eksctl utils associate-iam-oidc-provider --cluster $cluster_name --approve
```
6. Install velero cli - https://velero.io/docs/v1.6/basic-install/#install-the-cli
```bash
curl -sLO "https://github.com/vmware-tanzu/velero/releases/download/v1.14.1/velero-v1.14.1-linux-amd64.tar.gz"
tar -xzvf velero-v1.14.1-linux-amd64.tar.gz -C /tmp && rm velero-v1.14.1-linux-amd64.tar.gz
sudo mv /tmp/velero-v1.14.1-linux-amd64/velero /usr/local/bin
```
how to backup aws eks cluster with velero
1. Using s3 to export backup configmaps, secrets and pvc
```bash
# Replace <BUCKETNAME> and <REGION> with your own values below.
BUCKET=<BUCKETNAME>
REGION=$(aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]')
aws s3 mb s3://$BUCKET --region $REGION
cat > velero_policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeVolumes",
                "ec2:DescribeSnapshots",
                "ec2:CreateTags",
                "ec2:CreateVolume",
                "ec2:CreateSnapshot",
                "ec2:DeleteSnapshot"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:DeleteObject",
                "s3:PutObject",
                "s3:AbortMultipartUpload",
                "s3:ListMultipartUploadParts"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET}"
            ]
        }
    ]
}
EOF

aws iam create-policy \
    --policy-name VeleroAccessPolicy \
    --policy-document file://velero_policy.json

PRIMARY_CLUSTER=$(aws eks list-clusters --query clusters[0] --output text)
RECOVERY_CLUSTER=$(aws eks list-clusters --query clusters[1] --output text)
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

eksctl create iamserviceaccount \
    --cluster=$PRIMARY_CLUSTER \
    --name=velero-server \
    --namespace=velero \
    --role-name=eks-velero-backup \
    --role-only \
    --attach-policy-arn=arn:aws:iam::$ACCOUNT:policy/VeleroAccessPolicy \
    --approve

eksctl create iamserviceaccount \
    --cluster=$RECOVERY_CLUSTER \
    --name=velero-server \
    --namespace=velero \
    --role-name=eks-velero-recovery \
    --role-only \
    --attach-policy-arn=arn:aws:iam::$ACCOUNT:policy/VeleroAccessPolicy \
    --approve
```
values.yaml

export BUCKET=
export REGION_CODE=$(aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]')
export ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
```bash
configuration:
  backupStorageLocation:
  - bucket: $BUCKET
    provider: aws
  volumeSnapshotLocation:
  - config:
      region: $REGION_CODE
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
      eks.amazonaws.com/role-arn: "arn:aws:iam::${ACCOUNT}:role/eks-velero-backup"
# Add tolerations under the pod specification (server) section
pod:
  server:
    tolerations:
    - key: "eks.amazonaws.com/compute-type"
      operator: "Equal"
      value: "fargate"
      effect: "NoSchedule"
```
values_recovery.yaml
```bash
configuration:
  backupStorageLocation:
  - bucket: $BUCKET
    provider: aws
  volumeSnapshotLocation:
  - config:
      region: ap-southeast-1
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
      eks.amazonaws.com/role-arn: "arn:aws:iam::${ACCOUNT}:role/eks-velero-recovery"
# Add tolerations under the pod specification (server) section
pod:
  server:
    tolerations:
    - key: "eks.amazonaws.com/compute-type"
      operator: "Equal"
      value: "fargate"
      effect: "NoSchedule"
```
## How to replicate a new cluster from existing one
```bash
#!/bin/bash
REGION="ap-southeast-1"
# Function to retrieve details of an existing EKS cluster
get_cluster_details() {
  clusters=$1
  
  # Describe the EKS cluster to get VPC and subnet information
  cluster_info=$(aws eks describe-cluster --name "$clusters" --query "cluster.resourcesVpcConfig" --region $REGION --output json)
  export cluster_role=$(aws iam list-roles --query "Roles[*].RoleName" --region $REGION | grep "eks-cluster" | sed 's/[", ]//g')
  export fargate_role=$(aws iam list-roles --query "Roles[*].RoleName" --region $REGION | grep "eks-fargate-system-profile" | sed 's/[", ]//g')
  # Extract VPC ID, Subnet IDs, and Security Group IDs
  export vpcid=$(echo "$cluster_info" | jq -r '.vpcId')
  export subnet_1=$(echo "$cluster_info" | jq -r '.subnetIds[0]')
  export subnet_2=$(echo "$cluster_info" | jq -r '.subnetIds[1]')
  eks_sg=$(echo "$cluster_info" | jq -r '.securityGroupIds[0]')
  security_group_ids=$(echo "$cluster_info" | jq -r '.securityGroupIds[1]')

  echo "Details for EKS cluster: $cluster_name"
  echo "VPC ID: $vpcid"
  echo "Subnet IDs:"
  echo "$subnet_1 $subnet_2"
  echo "Security Group IDs:"
  echo "$eks_sg $security_group_ids"
  echo

  # Return the details
  echo "$vpc_id" "$subnet_ids" "$security_group_ids"
}

# Function to create a new EKS cluster using the existing cluster's VPC, subnet, and security groups
create_new_cluster() {
  original_cluster_name=$1
  new_cluster_name=$2

  # Get details of the existing cluster
  cluster_details=$(get_cluster_details "$original_cluster_name")
  
  # Split details into variables
  read -r vpc_id subnet_ids security_group_ids <<< "$cluster_details"

  # Convert subnet and security group IDs to comma-separated strings
  subnet_ids_csv=$(echo "$subnet_ids" | tr ' ' ',')
  security_group_ids_csv=$(echo "$security_group_ids" | tr ' ' ',')

  echo "Creating a new EKS cluster named: $new_cluster_name"
  echo "Using VPC ID: $vpc_id"
  echo "Subnets: $subnet_ids_csv"
  echo "Security Groups: $security_group_ids_csv"

  # Create a new EKS cluster
  aws eks create-cluster \
    --name "$new_cluster_name" \
    --role-arn "arn:aws:iam::YOUR_ACCOUNT_ID:role/YOUR_EKS_CLUSTER_ROLE" \
    --resources-vpc-config subnetIds="$subnet_ids_csv",securityGroupIds="$security_group_ids_csv" \
    --kubernetes-version 1.25

  echo "New EKS cluster creation initiated: $new_cluster_name"
}

# Retrieve the list of all EKS clusters in the current AWS account
export clusters=$(aws eks list-clusters --query "clusters[0]" --region $REGION --output text)

# Check if any clusters are returned
if [ -z "$clusters" ]; then
  echo "No EKS clusters found in the current AWS account."
else
  echo "EKS clusters in the current AWS account:"
  # Loop through the cluster names and display each
  echo $clusters

# Example usage
original_cluster_name=$clusters
get_cluster_details "$clusters"
export new_cluster_name="${original_cluster_name}02"  # Create a new cluster name by appending '02'

# Call the function to create a new EKS cluster using the existing cluster's details
# create_new_cluster "$original_cluster_name" "$new_cluster_name"
```
## Run this after the above script
```bash
alias k=kubectl; alias tf="terraform"; alias tfa="terraform apply --auto-approve"; alias tfd="terraform destroy --auto-approve"; alias tfm="terraform init; terraform fmt; terraform validate; terraform plan"; sudo yum install -y yum-utils shadow-utils; sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo; sudo yum -y install terraform;
```
```bash
bucket_name=$(aws eks list-clusters --query clusters[0] --output text);
REGION=$(aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]');
account_id=$(aws sts get-caller-identity --query Account --output text)
primary_cluster=$(aws eks list-clusters --query "clusters[0]" --region $REGION --output text);
recovery_cluster="${primary_cluster}02";
cluster_info=$(aws eks describe-cluster --name "$primary_cluster" --query "cluster.resourcesVpcConfig" --region $REGION --output json);
cluster_role=$(aws iam list-roles --query "Roles[*].RoleName" --region $REGION | grep "eks-cluster" | sed 's/[", ]//g' | head -n 1);
fargate_role=$(aws iam list-roles --query "Roles[*].RoleName" --region $REGION | grep "eks-fargate-system-profile" | sed 's/[", ]//g');
vpcid=$(echo "$cluster_info" | jq -r '.vpcId');
subnet_1=$(echo "$cluster_info" | jq -r '.subnetIds[0]');
subnet_2=$(echo "$cluster_info" | jq -r '.subnetIds[1]');
eks_sg=$(echo "$cluster_info" | jq -r '.securityGroupIds[0]');
aws_lb_role=$(aws iam list-roles --query Roles[*].RoleName | grep aws-load-balancer-controller | sed 's/[", ]//g')
echo REGION: $REGION; \
echo Primary Cluster: $primary_cluster; \
echo Recovery Cluster: $recovery_cluster; \
echo Cluster Role: $cluster_role; \
echo Fargate Role: $fargate_role; \
echo VPCID: $vpcid; \
echo SubNet1: $subnet_1; \
echo SubNet2: $subnet_2; \
echo EKS SG: $eks_sg; \
echo AWS Load Balancer: $aws_lb_role
```
```bash
tfm -var primary_cluster=$primary_cluster -var "recovery_eks_cluster=$recovery_cluster" -var "eks_role=$cluster_role" -var "fargate_role=$fargate_role" -var "vpcid=$vpcid" -var "subnet_1=$subnet_1" -var "subnet_2=$subnet_2" -var "eks_sg=$eks_sg" -var "account_id=$account_id" -var "region=$REGION" -var "aws_load_balancer_role=$aws_lb_role" -var "bucket_name=${bucket_name}-eks-velero-backups" -var "cluster_version=1.30"
```
```bash
bucket_name=$(aws eks list-clusters --query clusters[0] --output text);
primary_cluster=$(aws eks list-clusters --query clusters[0] --output text);
recovery_cluster=$(aws eks list-clusters --query clusters[1] --output text);
region=$(aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]');
account_id=$(aws sts get-caller-identity --query Account --output text)
tfm -var account_id=$account_id -var region=$region -var bucket_name=$bucket_name-eks-velero-backups -var primary_cluster=$primary_cluster -var recovery_cluster=$recovery_cluster
tfa -var account_id=$account_id -var region=$region -var bucket_name=$bucket_name-eks-velero-backups -var primary_cluster=$primary_cluster -var recovery_cluster=$recovery_cluster
```

## Troubleshooting
```bash
kubectl get events --sort-by='.lastTimestamp'
kubectl get ns velero -o json | jq '.spec.finalizers = []' | kubectl replace --raw "/api/v1/namespaces/velero/finalize" -f -
```
Resource - https://bluexp.netapp.com/blog/cbs-aws-blg-eks-back-up-how-to-back-up-and-restore-eks-with-velero

https://aws.amazon.com/blogs/containers/backup-and-restore-your-amazon-eks-cluster-resources-using-velero/

https://docs.vmware.com/en/VMware-Tanzu-Mission-Control/services/tanzumc-using/GUID-A0618B8D-8A28-4A5F-AC8C-5FF840277ADF.html

https://github.com/vmware-tanzu/velero-plugin-for-aws#install-and-start-velero
