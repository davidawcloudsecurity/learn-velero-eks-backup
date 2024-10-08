#!/bin/bash

SLEEP_TIME=60
COUNTER=0
MAX_CHECKS=15

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
  COUNTER=0 # Reset counter for each upgrade attempt

  echo "Upgrading cluster $CLUSTER_NAME to Kubernetes version $target_version..."

  # Start the cluster upgrade
  aws eks update-cluster-version \
    --name "$CLUSTER_NAME" \
    --region "$REGION" \
    --kubernetes-version "$target_version"

  if [[ $? -ne 0 ]]; then
    echo "Failed to start cluster upgrade to version $target_version."
    check_node_versions "$target_version"
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
      if [ "${COUNTER}" -ge "${MAX_CHECKS}" ]; then
        echo "Reached maximum checks (${MAX_CHECKS}). Exiting."
        exit 1
      fi
      echo "Waiting for ${SLEEP_TIME} seconds before checking again."
      sleep ${SLEEP_TIME}
      COUNTER=$((COUNTER+1))
    fi
  done
}

# Function to delete pods
delete_pods() {
  # Get all namespaces
  NAMESPACES=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')
  
  # Loop through each namespace
  for NAMESPACE in $NAMESPACES; do
    echo "Deleting all pods in namespace: $NAMESPACE"
    
    # Delete all pods in the current namespace
    kubectl delete pods --all --namespace="$NAMESPACE"
  
    if [[ $? -eq 0 ]]; then
      echo "All pods deleted successfully in namespace: $NAMESPACE"
    else
      echo "Failed to delete pods in namespace: $NAMESPACE"
    fi
  done
  echo "All pods in all namespaces have been deleted."
}

# Function to check node versions
check_node_versions() {
  local target_version=$1
  echo "Checking if all nodes are upgraded to version $target_version..."

  ALL_MATCH=true
  # Loop through all nodes and check their Kubelet versions
  for NODE in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
    NODE_VERSION=$(kubectl get node $NODE -o jsonpath='{.status.nodeInfo.kubeletVersion}')
    echo "Node $NODE is running version $NODE_VERSION"

    if [[ "$NODE_VERSION" != "v$target_version" ]]; then
      ALL_MATCH=false
      echo "Node $NODE has not been upgraded yet."
    fi
  done

  if [ "$ALL_MATCH" = true ]; then
    echo "All nodes are running the target version v$target_version."
  else
    echo "Some nodes have not been upgraded to the target version."
  fi

  export ALL_MATCH
}

# Function to restart deployments in all namespaces
restart_deployments() {
  echo "Restarting all deployments in all namespaces..."

  # Get all namespaces
  for NAMESPACE in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
    echo "Restarting deployments in namespace: $NAMESPACE"
    
    # Restart all deployments in the namespace
    kubectl rollout restart deployment --namespace="$NAMESPACE"

    if [[ $? -ne 0 ]]; then
      echo "Failed to restart deployments in namespace $NAMESPACE."
    else
      echo "Successfully restarted deployments in namespace $NAMESPACE."
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

    # Loop to ensure all nodes are upgraded before moving to the next version
    while true; do
      delete_pods
      
      # If all nodes match, break the loop and move to the next version
      if [ "$ALL_MATCH" = true ]; then
        echo "All nodes are ready for version $VERSION."
        break
      else
        echo "Not all nodes are upgraded to version $VERSION. Retrying..."
        check_node_versions "$VERSION"
      fi
      # Wait before retrying
      sleep ${SLEEP_TIME}
    done

    # Update the current version to the newly upgraded version
    CURRENT_VERSION="$VERSION"
  else
    echo "Cluster is already at or above version $VERSION. Skipping..."
  fi
done

echo "Cluster has been successfully upgraded to the target version $FINAL_VERSION."
