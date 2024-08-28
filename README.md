!#/bin/bash
# learn-velero-eks-backup
## Prerequisite
1. Install eksctl - https://eksctl.io/installation/
2. Download helm - https://github.com/helm/helm/releases
3. Create an IAM OIDC provider for your cluster - https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html
4. Install velero cli - https://velero.io/docs/v1.6/basic-install/#install-the-cli
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
```bash
configuration:
  backupStorageLocation:
  - bucket: eks-velero-backups
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
  - bucket: eks-velero-backups
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
  export cluster_role=$(aws iam list-roles --query "Roles[*].RoleName" --region $REGION | grep "eks-cluster" | sed 's/[",]//g; s/ //g')
  export fargate_role=$(aws iam list-roles --query "Roles[*].RoleName" --region $REGION | grep "eks-fargate-system-profile" | sed 's/[",]//g; s/ //g')
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
alias k=kubectl; alias tf="terraform"; alias tfa="terraform apply --auto-approve"; alias tfd="terraform destroy --auto-approve"; alias tfm="terraform init; terraform fmt; terraform validate; terraform plan"; sudo yum install -y yum-utils shadow-utils; sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo; sudo yum -y install terraform
tfm -var "eks_cluster=$new_cluster_name" -var "eks_role=$cluster_role" -var "fargate_role=$fargate_role" -var "vpcid=$vpcid" -var "subnet_1=$subnet_1" -var "subnet_2=$subnet_2" -var "eks_sg=$eks_sg"
```
Resource - https://bluexp.netapp.com/blog/cbs-aws-blg-eks-back-up-how-to-back-up-and-restore-eks-with-velero

https://aws.amazon.com/blogs/containers/backup-and-restore-your-amazon-eks-cluster-resources-using-velero/

https://stackoverflow.com/questions/66405794/not-authorized-to-perform-stsassumerolewithwebidentity-403
