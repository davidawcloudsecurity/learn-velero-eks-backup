#!/bin/bash

COUNTER=0
MAX_CHECKS=15
SLEEP_TIME=60

# Check if both inputs are provided
if [ "$#" -ne 3 ]; then
  echo "Error: Usage: $0 <cluster_name> <region> <target_version>"
  exit 1
fi

# Take cluster name, region, and target version as input parameters
CLUSTER_NAME=$1
REGION=$2
TARGET_VERSION=$3

# Get the current cluster version
CURRENT_VERSION=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$REGION" \
  --query 'cluster.version' \
  --output text)

echo "Cluster Name: $CLUSTER_NAME"
echo "Region: $REGION"
echo "Current version: $CURRENT_VERSION"
echo "Target version: $TARGET_VERSION"

# Function to delete pods
delete_pods() {
  NAMESPACES=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')
  
  for NAMESPACE in $NAMESPACES; do
    echo "Deleting all pods in namespace: $NAMESPACE"
    kubectl delete pods --all --namespace="$NAMESPACE"
  done
}

# Function to check node versions
check_node_versions() {
  local target_version=$1
  echo "Checking if all nodes are upgraded to version $target_version..."

  ALL_MATCH=true
  for NODE in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
    NODE_VERSION=$(kubectl get node $NODE -o jsonpath='{.status.nodeInfo.kubeletVersion}' | cut -d'.' -f1-2)
    if [[ "$NODE_VERSION" != "v$target_version" ]]; then
      ALL_MATCH=false
      echo "Node $NODE has not been upgraded yet, running version $NODE_VERSION"
    fi
  done
  if [ "$ALL_MATCH" != true ]; then
    delete_pods
    # renew kubeconfig here
  fi
}

# Function to increment the version
increment_version() {
  local version=$1
  local next_version=$(echo $version | awk -F. '{print $1"."$2+1}')
  echo "$next_version"
}

# Start upgrading incrementally
while [[ "$CURRENT_VERSION" != "$TARGET_VERSION" ]]; do
  NEXT_VERSION=$(increment_version "$CURRENT_VERSION")

  # Stop if the next version exceeds the target
  if [[ "$NEXT_VERSION" > "$TARGET_VERSION" ]]; then
    NEXT_VERSION="$TARGET_VERSION"
  fi

  echo "Upgrading cluster from version $CURRENT_VERSION to $NEXT_VERSION..."

  aws eks update-cluster-version \
    --name "$CLUSTER_NAME" \
    --region "$REGION" \
    --kubernetes-version "$NEXT_VERSION"
    
  if [[ $? -ne 0 ]]; then
    echo "Error: Failed to upgrade to version $NEXT_VERSION."
    exit 1
  fi

  echo "Waiting for the cluster to become active..."
  sleep ${SLEEP_TIME}

  COUNTER=0
  while true; do
    STATUS=$(aws eks describe-cluster \
      --name "$CLUSTER_NAME" \
      --region "$REGION" \
      --query 'cluster.status' \
      --output text)

    if [[ "$STATUS" == "ACTIVE" ]]; then
      echo "Cluster upgraded to version $NEXT_VERSION successfully."
      break
    else
      echo "Cluster status: $STATUS. Waiting for the upgrade to complete..."
      if [ "${COUNTER}" -ge "${MAX_CHECKS}" ]; then
        echo "Error: Reached maximum checks (${MAX_CHECKS}). Exiting."
        exit 1
      fi
      sleep ${SLEEP_TIME}
      COUNTER=$((COUNTER+1))
    fi
  done

  # Check and wait until all nodes are upgraded
  while true; do
    check_node_versions "$NEXT_VERSION"

    if [ "$ALL_MATCH" = true ]; then
      echo "All nodes are running version v$NEXT_VERSION."
      break
    else
      echo "Not all nodes are upgraded to version $NEXT_VERSION. Retrying..."
      sleep ${SLEEP_TIME}
    fi
  done

  # Set the current version to the next version for the next iteration
  CURRENT_VERSION="$NEXT_VERSION"
done

echo "Cluster upgrade to target version $TARGET_VERSION completed successfully."
