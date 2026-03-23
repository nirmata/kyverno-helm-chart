#!/bin/bash
# Script to fix Helm ownership metadata for existing ClusterPolicies and ValidatingPolicies
# Use this when policies exist but don't have Helm ownership labels/annotations

set -e

RELEASE_NAME="${1:-trinet-policies}"
NAMESPACE="${2:-kyverno}"
AUTO_YES="${AUTO_YES:-false}"

if [ -z "$RELEASE_NAME" ]; then
  echo "Usage: $0 <release-name> [namespace]"
  echo "Example: $0 trinet-policies kyverno"
  echo ""
  echo "Environment variables:"
  echo "  AUTO_YES=true  - Skip confirmation prompts"
  exit 1
fi

echo "Fixing Helm ownership for Kyverno Policies"
echo "==========================================="
echo "Release Name: $RELEASE_NAME"
echo "Namespace: $NAMESPACE"
echo ""

# Function to fix ownership for a resource type
fix_ownership() {
  local resource_type=$1
  local resource_kind=$2
  
  echo "Checking $resource_kind..."
  
  # Get resources that don't have Helm ownership
  RESOURCES=$(kubectl get "$resource_type" -o json 2>/dev/null | \
    jq -r ".items[] | select(.metadata.labels.\"app.kubernetes.io/managed-by\" != \"Helm\") | .metadata.name" 2>/dev/null || echo "")
  
  if [ -z "$RESOURCES" ]; then
    echo "  ✓ All $resource_kind already have Helm ownership"
    return 0
  fi
  
  RESOURCE_COUNT=$(echo "$RESOURCES" | grep -v '^$' | wc -l | tr -d ' ')
  echo "  Found $RESOURCE_COUNT $resource_kind without Helm ownership"
  
  if [ "$RESOURCE_COUNT" -eq 0 ]; then
    return 0
  fi
  
  # Ask for confirmation (unless AUTO_YES is set)
  if [ "$AUTO_YES" != "true" ]; then
    read -p "  Do you want to add Helm ownership metadata to these $resource_kind? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "  Skipped."
      return 1
    fi
  else
    echo "  Auto-confirming (AUTO_YES=true)..."
  fi
  
  # Add Helm ownership to each resource
  SUCCESS=0
  FAILED=0
  
  for resource in $RESOURCES; do
    if [ -z "$resource" ]; then
      continue
    fi
    
    echo -n "    Fixing $resource... "
    
    # Add labels and annotations
    if kubectl label "$resource_type" "$resource" \
      app.kubernetes.io/managed-by=Helm \
      app.kubernetes.io/instance="$RELEASE_NAME" \
      --overwrite 2>/dev/null && \
      kubectl annotate "$resource_type" "$resource" \
      meta.helm.sh/release-name="$RELEASE_NAME" \
      meta.helm.sh/release-namespace="$NAMESPACE" \
      --overwrite 2>/dev/null; then
      echo "✓"
      SUCCESS=$((SUCCESS + 1))
    else
      echo "✗"
      FAILED=$((FAILED + 1))
    fi
  done
  
  echo "  Summary: $SUCCESS successful, $FAILED failed"
  return $FAILED
}

# Fix ClusterPolicies
echo "Step 1: Fixing ClusterPolicies..."
fix_ownership "clusterpolicies" "ClusterPolicies"
CLUSTER_POLICY_FAILED=$?

echo ""

# Fix ValidatingPolicies
echo "Step 2: Fixing ValidatingPolicies..."
fix_ownership "validatingpolicies.policies.kyverno.io" "ValidatingPolicies"
VALIDATING_POLICY_FAILED=$?

echo ""
echo "=================================================="
echo "Summary:"
echo ""

if [ $CLUSTER_POLICY_FAILED -eq 0 ] && [ $VALIDATING_POLICY_FAILED -eq 0 ]; then
  echo "✓ All policies now have Helm ownership metadata"
  echo ""
  echo "You can now install/upgrade the Helm release:"
  echo "  helm install $RELEASE_NAME . --namespace $NAMESPACE"
  exit 0
else
  echo "✗ Some policies failed to update. Check permissions and try again."
  echo ""
  echo "You can also manually fix ownership:"
  echo "  kubectl label <resource-type> <name> app.kubernetes.io/managed-by=Helm --overwrite"
  echo "  kubectl annotate <resource-type> <name> meta.helm.sh/release-name=$RELEASE_NAME --overwrite"
  exit 1
fi

