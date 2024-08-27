!#/bin/bash
# learn-velero-eks-backup
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
## How to replicate a new cluster from existing one
#!/bin/bash

# Function to retrieve details of an existing EKS cluster
get_cluster_details() {
  cluster_name=$1

  # Describe the EKS cluster to get VPC and subnet information
  cluster_info=$(aws eks describe-cluster --name "$cluster_name" --query "cluster.resourcesVpcConfig" --output json)

  # Extract VPC ID, Subnet IDs, and Security Group IDs
  vpc_id=$(echo "$cluster_info" | jq -r '.vpcId')
  subnet_ids=$(echo "$cluster_info" | jq -r '.subnetIds[]')
  security_group_ids=$(echo "$cluster_info" | jq -r '.securityGroupIds[]')

  echo "Details for EKS cluster: $cluster_name"
  echo "VPC ID: $vpc_id"
  echo "Subnet IDs:"
  echo "$subnet_ids"
  echo "Security Group IDs:"
  echo "$security_group_ids"
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
clusters=$(aws eks list-clusters --query "clusters[0]" --output text)

# Check if any clusters are returned
if [ -z "$clusters" ]; then
  echo "No EKS clusters found in the current AWS account."
else
  echo "EKS clusters in the current AWS account:"
  # Loop through the cluster names and display each
  echo $clusters

# Example usage
original_cluster_name=$clusters
new_cluster_name="${original_cluster_name}02"  # Create a new cluster name by appending '02'

# Call the function to create a new EKS cluster using the existing cluster's details
create_new_cluster "$original_cluster_name" "$new_cluster_name"
```
Resource - https://bluexp.netapp.com/blog/cbs-aws-blg-eks-back-up-how-to-back-up-and-restore-eks-with-velero

https://aws.amazon.com/blogs/containers/backup-and-restore-your-amazon-eks-cluster-resources-using-velero/

https://stackoverflow.com/questions/66405794/not-authorized-to-perform-stsassumerolewithwebidentity-403
