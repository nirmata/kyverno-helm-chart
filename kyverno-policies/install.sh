#!/usr/bin/env bash
# Install policies without Helm's concurrent API calls, which often exceed Kyverno's
# policy validation webhook timeout (10s) on large policy sets.
set -euo pipefail
RELEASE_NAME="${RELEASE_NAME:-trinet-policies}"
NAMESPACE="${NAMESPACE:-kyverno}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$ROOT"
echo "Rendering Helm chart..."
helm template "$RELEASE_NAME" . --namespace "$NAMESPACE" | kubectl apply --server-side --force-conflicts -f -

echo ""
echo "ClusterPolicy:"
kubectl get clusterpolicy -o custom-columns=NAME:.metadata.name,READY:.status.conditions[0].status,REASON:.status.conditions[0].reason 2>/dev/null | head -50

echo ""
echo "ValidatingPolicy:"
kubectl get validatingpolicy.policies.kyverno.io -o wide 2>/dev/null || true
