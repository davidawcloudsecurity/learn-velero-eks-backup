#!/bin/bash

# Check if both inputs are provided
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <cluster_name> <region>"
  exit 1
fi

# Take cluster name and region as input parameters
CLUSTER_NAME=$1
REGION=$2

# Target final Kubernetes version
FINAL_VERSION="1.30"

# Output retrieved values for confirmation
echo "Cluster Name: $CLUSTER_NAME"
echo "Region: $REGION"

# Define an array of versions to increment through
VERSIONS=("1.25" "1.26" "1.27" "1.28" "1.29" "1.30")

# Function to upgrade the EKS cluster
upgrade_cluster_version() {
  local target_version=$1

  echo "Upgrading cluster $CLUSTER_NAME to Kubernetes version $target_version..."

  # Start the cluster upgrade
  aws eks update-cluster-version \
    --name "$CLUSTER_NAME" \
    --region "$REGION" \
    --kubernetes-version "$target_version"

  if [[ $? -ne 0 ]]; then
    echo "Failed to start cluster upgrade to version $target_version. Exiting."
    exit 1
  fi

  # Monitor the status of the upgrade
  while true; do
    STATUS=$(aws eks describe-cluster \
      --name "$CLUSTER_NAME" \
      --region "$REGION" \
      --query 'cluster.status' \
      --output text)

    if [[ "$STATUS" == "ACTIVE" ]]; then
      echo "Cluster upgrade to version $target_version completed successfully."
      break
    else
      echo "Cluster status: $STATUS. Waiting for the upgrade to complete..."
      sleep 60
    fi
  done
}

# Get the current cluster version
CURRENT_VERSION=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$REGION" \
  --query 'cluster.version' \
  --output text)

echo "Current Kubernetes version: $CURRENT_VERSION"

# Loop through the version upgrades
for VERSION in "${VERSIONS[@]}"; do
  # Only upgrade if the current version is less than the target version
  if [[ "$CURRENT_VERSION" < "$VERSION" ]]; then
    # Upgrade cluster version
    upgrade_cluster_version "$VERSION"

    # After upgrade, set the current version to the newly upgraded version
    CURRENT_VERSION="$VERSION"
  else
    echo "Cluster is already at or above version $VERSION. Skipping..."
  fi
done

echo "Cluster has been successfully upgraded to the target version $FINAL_VERSION."
