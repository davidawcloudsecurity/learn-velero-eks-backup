#!/bin/bash
COUNTER=0
MAX_CHECKS=15
SLEEP_TIME=60
target_version=1.25

echo "Current time: $(date +"%Y-%m-%d %H:%M:%S")" >> record_file

# Check if both inputs are provided
if [ "$#" -ne 3 ]; then
  echo "Error: Usage: $0 <cluster_name> <region> <target_version>"
  exit 1
fi

# Take cluster name and region as input parameters
CLUSTER_NAME=$1
REGION=$2
TARGET_VERSION=$3

# Get the current cluster version
CURRENT_VERSION=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$REGION" \
  --query 'cluster.version' \
  --output text)

# Output retrieved values for confirmation
echo "Cluster Name: $CLUSTER_NAME"
echo "Region: $REGION"
echo "Current version: $CURRENT_VERSION"
echo "Target version: $TARGET_VERSION"

# Function to delete pods
delete_pods() {
  # Get all namespaces
  NAMESPACES=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')
  
  # Loop through each namespace
  for NAMESPACE in $NAMESPACES; do
    echo "Deleting all pods in namespace: $NAMESPACE"
    
    # Delete all pods in the current namespace
    OUTPUT=$(kubectl delete pods --all --namespace="$NAMESPACE")
    STATUS=$?
    
    if echo "$OUTPUT" | grep -q "No resources found"; then
      echo "No pods found to delete in namespace: $NAMESPACE"
    fi
    # Check if the command was successful or if no resources were found
    if [[ $STATUS -eq 0 ]]; then
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
    NODE_VERSION=$(kubectl get node $NODE -o jsonpath='{.status.nodeInfo.kubeletVersion}' | cut -d'.' -f1-2)
    echo "Node $NODE is running version $NODE_VERSION"

    if [[ "$NODE_VERSION" != "v$target_version" ]]; then
      ALL_MATCH=false
      echo "Node $NODE has not been upgraded yet."
    fi
  done

  if [ "$ALL_MATCH" = true ]; then
    echo "All nodes are running the target version v$target_version."
  fi
}

# Start the cluster upgrade
  aws eks update-cluster-version \
    --name "$CLUSTER_NAME" \
    --region "$REGION" \
    --kubernetes-version "$target_version" > /dev/null 2>&1;

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
        echo "Error: Reached maximum checks (${MAX_CHECKS}). Exiting."
        exit 1
      fi
      echo "Waiting for ${SLEEP_TIME} seconds before checking again."
      sleep ${SLEEP_TIME}
      COUNTER=$((COUNTER+1))
    fi
  done 

if [[ $? -ne 0 ]]; then
    echo "Error: Failed to start cluster upgrade to version $target_version."
    exit 1
fi

# Loop to ensure all nodes are upgraded before moving to the next version
while true; do
  check_node_versions "$target_version"

  # If all nodes match, break the loop and move to the next version
  if [ "$ALL_MATCH" = true ]; then
    echo "All nodes are ready for version $target_version."
    break
  else
    echo "Not all nodes are upgraded to version $target_version. Retrying..."
    delete_pods
    echo "Sleep ${SLEEP_TIME}"
    sleep ${SLEEP_TIME}        
  fi
done
