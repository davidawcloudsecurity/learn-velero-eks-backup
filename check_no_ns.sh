#!/bin/bash
# Check for nodes with no namespaces
# Ensure kubectl is installed and configured for the correct EKS cluster

echo "Checking for nodes with no pods scheduled..."

# Get all nodes in the cluster
all_nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')

# Loop through each node and check for non-terminated pods
for node in $all_nodes; do
  # Count non-terminated pods on the node
  pod_count=$(kubectl get pods --all-namespaces --field-selector spec.nodeName=$node,status.phase!=Succeeded,status.phase!=Failed -o json | jq '.items | length')
  
  # If the node has no non-terminated pods, print the node name
  if [[ "$pod_count" -eq 0 ]]; then
    echo "Node with no running pods: $node"
  fi
done

echo "Done."
