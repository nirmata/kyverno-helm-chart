#!/bin/bash
# Script to apply Kyverno policies in batches to avoid webhook timeouts
# This script applies policies one at a time with retries

set -e

NAMESPACE="${NAMESPACE:-kyverno}"
RELEASE_NAME="${RELEASE_NAME:-trinet-policies}"
BATCH_SIZE="${BATCH_SIZE:-5}"
RETRY_DELAY="${RETRY_DELAY:-5}"
MAX_RETRIES="${MAX_RETRIES:-3}"

echo "Kyverno Policies - Batch Application Script"
echo "==========================================="
echo "Namespace: $NAMESPACE"
echo "Release Name: $RELEASE_NAME"
echo "Batch Size: $BATCH_SIZE"
echo "Retry Delay: ${RETRY_DELAY}s"
echo "Max Retries: $MAX_RETRIES"
echo ""

# Step 1: Increase webhook timeout first
echo "Step 1: Increasing webhook timeout..."
PATCHED_VALIDATING=false
PATCHED_MUTATING=false

# Try to patch validating webhook - check if it exists and has the right structure
if kubectl get validatingwebhookconfiguration kyverno-policy-validating-webhook-cfg &>/dev/null; then
  CURRENT_TIMEOUT=$(kubectl get validatingwebhookconfiguration kyverno-policy-validating-webhook-cfg -o jsonpath='{.webhooks[0].timeoutSeconds}' 2>/dev/null || echo "10")
  if [ "$CURRENT_TIMEOUT" != "30" ]; then
    if kubectl patch validatingwebhookconfiguration kyverno-policy-validating-webhook-cfg \
      --type='json' \
      -p='[{"op": "replace", "path": "/webhooks/0/timeoutSeconds", "value": 30}]' 2>/dev/null; then
      PATCHED_VALIDATING=true
      echo "  ✓ Validating webhook timeout: 10s → 30s"
    else
      echo "  ⚠ Could not patch validating webhook timeout (may require cluster-admin)"
    fi
  else
    echo "  ✓ Validating webhook timeout already set to 30s"
    PATCHED_VALIDATING=true
  fi
else
  echo "  ⚠ Validating webhook configuration not found"
fi

# Try to patch mutating webhook
if kubectl get mutatingwebhookconfiguration kyverno-policy-mutating-webhook-cfg &>/dev/null; then
  CURRENT_TIMEOUT=$(kubectl get mutatingwebhookconfiguration kyverno-policy-mutating-webhook-cfg -o jsonpath='{.webhooks[0].timeoutSeconds}' 2>/dev/null || echo "10")
  if [ "$CURRENT_TIMEOUT" != "30" ]; then
    if kubectl patch mutatingwebhookconfiguration kyverno-policy-mutating-webhook-cfg \
      --type='json' \
      -p='[{"op": "replace", "path": "/webhooks/0/timeoutSeconds", "value": 30}]' 2>/dev/null; then
      PATCHED_MUTATING=true
      echo "  ✓ Mutating webhook timeout: 10s → 30s"
    else
      echo "  ⚠ Could not patch mutating webhook timeout (may require cluster-admin)"
    fi
  else
    echo "  ✓ Mutating webhook timeout already set to 30s"
    PATCHED_MUTATING=true
  fi
else
  echo "  ⚠ Mutating webhook configuration not found"
fi

if [ "$PATCHED_VALIDATING" = "true" ] || [ "$PATCHED_MUTATING" = "true" ]; then
  echo "✓ Webhook timeouts configured"
else
  echo "⚠ Could not patch webhook timeouts - will apply policies in smaller batches"
fi
echo ""

# Step 2: Render all templates
echo "Step 2: Rendering Helm templates..."
TEMP_FILE=$(mktemp)
helm template "$RELEASE_NAME" . \
  --namespace "$NAMESPACE" > "$TEMP_FILE"

POLICY_COUNT=$(grep -c "^kind: ClusterPolicy\|^kind: ValidatingPolicy" "$TEMP_FILE" || echo "0")
echo "✓ Found $POLICY_COUNT policies to apply"
echo ""

# Step 3: Split into individual policy files
echo "Step 3: Splitting policies into individual files..."
SPLIT_DIR=$(mktemp -d)
cd "$SPLIT_DIR"

# Split by --- separator
csplit -s -f policy- -b "%02d.yaml" "$TEMP_FILE" '/^---$/' '{*}' 2>/dev/null || {
  # If csplit fails, try awk
  awk '/^---$/{close(f); f="policy-"++i".yaml"} {print > f}' "$TEMP_FILE"
}

POLICY_FILES=(policy-*.yaml)
POLICY_COUNT=${#POLICY_FILES[@]}
echo "✓ Split into $POLICY_COUNT policy files"
echo ""

# Step 4: Apply policies in batches with retries
echo "Step 4: Applying policies in batches of $BATCH_SIZE..."
SUCCESS_COUNT=0
FAILED_COUNT=0
FAILED_POLICIES=()

apply_policy() {
  local policy_file=$1
  local retry_count=0
  
  while [ $retry_count -lt $MAX_RETRIES ]; do
    if kubectl apply -f "$policy_file" --server-side --force-conflicts 2>/dev/null; then
      return 0
    fi
    
    retry_count=$((retry_count + 1))
    if [ $retry_count -lt $MAX_RETRIES ]; then
      echo "  Retrying ($retry_count/$MAX_RETRIES) after ${RETRY_DELAY}s..."
      sleep "$RETRY_DELAY"
    fi
  done
  
  return 1
}

BATCH_NUM=0
for i in "${!POLICY_FILES[@]}"; do
  POLICY_FILE="${POLICY_FILES[$i]}"
  
  # Start new batch
  if [ $((i % BATCH_SIZE)) -eq 0 ]; then
    BATCH_NUM=$((BATCH_NUM + 1))
    echo "Batch $BATCH_NUM:"
  fi
  
  POLICY_NAME=$(grep -m1 "^  name:" "$POLICY_FILE" | awk '{print $2}' | tr -d '"' || echo "unknown")
  echo -n "  Applying $POLICY_NAME... "
  
  if apply_policy "$POLICY_FILE"; then
    echo "✓"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    echo "✗"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    FAILED_POLICIES+=("$POLICY_NAME")
  fi
  
  # Small delay between policies
  sleep 1
done

# Cleanup
rm -rf "$SPLIT_DIR"
rm -f "$TEMP_FILE"

echo ""
echo "=================================================="
echo "Application Summary:"
echo "  Successful: $SUCCESS_COUNT"
echo "  Failed: $FAILED_COUNT"
echo ""

if [ $FAILED_COUNT -gt 0 ]; then
  echo "Failed policies:"
  for policy in "${FAILED_POLICIES[@]}"; do
    echo "  - $policy"
  done
  echo ""
  echo "You can retry failed policies manually or increase MAX_RETRIES/BATCH_SIZE"
  exit 1
else
  echo "✓ All policies applied successfully!"
  echo ""
  echo "Verification:"
  echo "  ClusterPolicies: $(kubectl get clusterpolicies --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  echo "  ValidatingPolicies: $(kubectl get validatingpolicies --no-headers 2>/dev/null | wc -l | tr -d ' ')"
fi

