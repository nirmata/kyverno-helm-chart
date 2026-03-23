# Troubleshooting Guide

## Error: Webhook Timeout Issues

### Problem

When installing policies, you see webhook timeout errors:

```
Error: Internal error occurred: failed calling webhook "validate-policy.kyverno.svc": 
failed to call webhook: Post "https://kyverno-svc.kyverno.svc:443/policyvalidate?timeout=10s": 
context deadline exceeded
```

### Solution 1: Use Batch Application Script (Recommended)

Use the provided script that applies policies in batches:

```bash
./apply-policies.sh
```

This script:
- Automatically increases webhook timeout to 30s
- Applies policies in small batches (default: 5 at a time)
- Retries failed policies up to 3 times
- Provides progress feedback and summary

### Solution 2: Increase Webhook Timeout First

```bash
# Increase validating webhook timeout
kubectl patch validatingwebhookconfiguration kyverno-policy-validating-webhook-cfg \
  --type='json' \
  -p='[{"op": "replace", "path": "/webhooks/0/timeoutSeconds", "value": 30}]'

# Increase mutating webhook timeout
kubectl patch mutatingwebhookconfiguration kyverno-policy-mutating-webhook-cfg \
  --type='json' \
  -p='[{"op": "replace", "path": "/webhooks/0/timeoutSeconds", "value": 30}]'

# Then retry Helm install
helm install trinet-policies . --namespace kyverno --timeout 10m
```

### Solution 3: Apply Directly with kubectl

```bash
# Render templates
helm template trinet-policies . --namespace kyverno > /tmp/policies.yaml

# Apply directly (handles timeouts better)
kubectl apply -f /tmp/policies.yaml --server-side --force-conflicts
```

## Error: "invalid ownership metadata"

### Problem

When installing a Helm chart, you see:

```
Error: INSTALLATION FAILED: Unable to continue with install: 
ValidatingPolicy "disallow-capabilities-strict" exists and cannot be imported: 
invalid ownership metadata; missing key "app.kubernetes.io/managed-by"
```

### Solution: Fix Ownership Metadata

**Quick Fix (Interactive):**
```bash
./fix-helm-ownership.sh trinet-policies kyverno
```

**Quick Fix (Non-Interactive):**
```bash
AUTO_YES=true ./fix-helm-ownership.sh trinet-policies kyverno
```

**One-Liner (No Script):**
```bash
RELEASE_NAME="trinet-policies"
NAMESPACE="kyverno"

# Fix all ValidatingPolicies
for policy in $(kubectl get validatingpolicies -o jsonpath='{.items[*].metadata.name}'); do
  kubectl label validatingpolicy "$policy" app.kubernetes.io/managed-by=Helm app.kubernetes.io/instance="$RELEASE_NAME" --overwrite
  kubectl annotate validatingpolicy "$policy" meta.helm.sh/release-name="$RELEASE_NAME" meta.helm.sh/release-namespace="$NAMESPACE" --overwrite
done

# Fix all ClusterPolicies
for policy in $(kubectl get clusterpolicies -o jsonpath='{.items[*].metadata.name}'); do
  kubectl label clusterpolicy "$policy" app.kubernetes.io/managed-by=Helm app.kubernetes.io/instance="$RELEASE_NAME" --overwrite
  kubectl annotate clusterpolicy "$policy" meta.helm.sh/release-name="$RELEASE_NAME" meta.helm.sh/release-namespace="$NAMESPACE" --overwrite
done
```

Or fix manually:

```bash
RELEASE_NAME="trinet-policies"
NAMESPACE="kyverno"

# Fix ValidatingPolicies
kubectl get validatingpolicies -o json | \
  jq -r '.items[] | select(.metadata.labels."app.kubernetes.io/managed-by" != "Helm") | .metadata.name' | \
  while read policy; do
    kubectl label validatingpolicy "$policy" \
      app.kubernetes.io/managed-by=Helm \
      app.kubernetes.io/instance="$RELEASE_NAME" \
      --overwrite
    kubectl annotate validatingpolicy "$policy" \
      meta.helm.sh/release-name="$RELEASE_NAME" \
      meta.helm.sh/release-namespace="$NAMESPACE" \
      --overwrite
  done

# Fix ClusterPolicies (if any)
kubectl get clusterpolicies -o json | \
  jq -r '.items[] | select(.metadata.labels."app.kubernetes.io/managed-by" != "Helm") | .metadata.name' | \
  while read policy; do
    kubectl label clusterpolicy "$policy" \
      app.kubernetes.io/managed-by=Helm \
      app.kubernetes.io/instance="$RELEASE_NAME" \
      --overwrite
    kubectl annotate clusterpolicy "$policy" \
      meta.helm.sh/release-name="$RELEASE_NAME" \
      meta.helm.sh/release-namespace="$NAMESPACE" \
      --overwrite
  done
```

## Error: "apiVersion not set, kind not set"

### Problem
Helm fails with:
```
Error: INSTALLATION FAILED: unable to build kubernetes objects from release manifest: 
error validating "": error validating data: [apiVersion not set, kind not set]
```

### Cause
This error occurs when there are files in the `templates/` directory that don't contain valid Kubernetes resources. Common causes:
- Corrupted files (e.g., containing "404: Not Found" or error messages)
- Empty files
- Files with only comments or whitespace
- Files that are not Kubernetes manifests

### Solution

1. **Validate templates before installing:**
   ```bash
   ./validate-templates.sh
   ```

2. **Find invalid files manually:**
   ```bash
   for file in templates/*.yaml; do
     if ! grep -q "^apiVersion:" "$file" 2>/dev/null; then
       echo "Invalid: $file"
       head -3 "$file"
     fi
   done
   ```

3. **Remove or fix invalid files:**
   ```bash
   # Remove corrupted files
   rm templates/invalid-file.yaml
   
   # Or fix them by adding proper Kubernetes resource structure
   ```

4. **Test before installing:**
   ```bash
   helm template test . --namespace kyverno
   helm install trinet-policies . --namespace kyverno --dry-run
   ```

## Important: Correct Directory

**Always run Helm commands from the `kyverno-policies` directory, not the repository root:**

```bash
# ✅ Correct
cd kyverno-policies
helm install trinet-policies . --namespace kyverno

# ❌ Wrong (will fail)
cd ..
helm install trinet-policies . --namespace kyverno
```

## Validation Script

Use the provided validation script to check templates before installation:

```bash
./validate-templates.sh
```

This script:
- Checks all YAML files in `templates/` for `apiVersion` and `kind`
- Warns about files containing error patterns (404, "not found", etc.)
- Tests Helm template rendering
- Reports which files are invalid

## Prevention

1. **Add to .helmignore**: Update `.helmignore` to exclude invalid files:
   ```
   *404*
   *Not Found*
   *error*
   ```

2. **Validate before committing**: Run `./validate-templates.sh` before committing changes

3. **Use CI/CD**: Add validation to your CI/CD pipeline

## Common Issues

### Issue: File contains "404: Not Found"
**Solution**: This usually happens when a file download failed. Delete the file or re-download it.

### Issue: Empty template file
**Solution**: Either add a valid Kubernetes resource or remove the file.

### Issue: File has only comments
**Solution**: Helm templates must contain actual Kubernetes resources, not just comments.

## Getting Help

If issues persist:
1. Run `helm template test .` to see detailed errors
2. Check Helm version: `helm version`
3. Verify Chart.yaml exists and is valid
4. Check that all template files are valid YAML

