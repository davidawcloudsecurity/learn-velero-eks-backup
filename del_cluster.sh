#!/bin/bash

# Check if both cluster name and region are provided
if [ $# -lt 2 ]; then
  echo "Usage: $0 $(aws eks list-clusters --query clusters --output text) <region>"
  exit 1
fi

# Use the inputs passed to the script
CLUSTER_NAME=$1
REGION=$2

# Function to check if a Fargate profile is deleted
function wait_for_fargate_profile_deletion() {
  local profile_name=$1
  echo "Waiting for Fargate profile '$profile_name' to be deleted..."

  while true; do
    # Check if the Fargate profile exists
    PROFILE_STATUS=$(aws eks describe-fargate-profile \
      --cluster-name $CLUSTER_NAME \
      --fargate-profile-name $profile_name \
      --region $REGION \
      --query 'fargateProfile.status' --output text 2>/dev/null)

    if [ "$PROFILE_STATUS" == "None" ] || [ "$PROFILE_STATUS" == "" ]; then
      echo "Fargate profile '$profile_name' has been deleted."
      break
    else
      echo "Fargate profile '$profile_name' still deleting... status: $PROFILE_STATUS"
      sleep 10  # Wait 10 seconds before checking again
    fi
  done
}

# Function to check if the EKS cluster is deleted
function wait_for_cluster_deletion() {
  echo "Waiting for EKS cluster '$CLUSTER_NAME' to be deleted..."

  while true; do
    # Check if the EKS cluster exists
    CLUSTER_STATUS=$(aws eks describe-cluster \
      --name $CLUSTER_NAME \
      --region $REGION \
      --query 'cluster.status' --output text 2>/dev/null)

    if [ "$CLUSTER_STATUS" == "None" ] || [ "$CLUSTER_STATUS" == "" ]; then
      echo "EKS cluster '$CLUSTER_NAME' has been deleted."
      break
    else
      echo "EKS cluster '$CLUSTER_NAME' still deleting... status: $CLUSTER_STATUS"
      sleep 10  # Wait 10 seconds before checking again
    fi
  done
}

# Step 1: Delete Fargate profiles
echo "Listing Fargate profiles for cluster '$CLUSTER_NAME'..."
FARGATE_PROFILES=$(aws eks list-fargate-profiles --cluster-name $CLUSTER_NAME --region $REGION --query 'fargateProfileNames' --output text)

for PROFILE in $FARGATE_PROFILES; do
  echo "Deleting Fargate profile: $PROFILE"
  aws eks delete-fargate-profile --cluster-name $CLUSTER_NAME --fargate-profile-name $PROFILE --region $REGION > /dev/null 2>&1

  # Wait for the profile to be completely deleted before moving to the next one
  wait_for_fargate_profile_deletion $PROFILE
done

# Step 2: Delete EKS cluster
echo "Deleting EKS cluster: $CLUSTER_NAME"
aws eks delete-cluster --name $CLUSTER_NAME --region $REGION > /dev/null 2>&1

# Step 3: Wait for the EKS cluster to be deleted
wait_for_cluster_deletion

echo "Cluster '$CLUSTER_NAME' and all associated Fargate profiles have been deleted successfully."
