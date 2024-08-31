#!/bin/bash

# Ensure kubectl is installed and configured for the correct EKS cluster

echo "Fetching pod IP addresses from EKS cluster..."

# Get all pods in all namespaces with their IP addresses and names
kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{.status.podIP}{" "}{.metadata.name}{"\n"}{end}' | column -t
