# Kyverno Policies Helm Chart

Helm chart for deploying Kyverno policies to Kubernetes clusters.

## Quick Start

### Prerequisites

- Kubernetes cluster with Kyverno installed
- Helm 3.x
- kubectl configured for your cluster
- **Recommended for `helm install`**: Kyverno admission controller with **multiple replicas** (for example `kubectl scale deploy kyverno-admission-controller -n kyverno --replicas=3`). A single replica on a small cluster often hits the **10s** policy validation webhook limit when many policies are applied at once.

### Installation

**Important**: Always run Helm commands from the `kyverno-policies` directory:

```bash
cd kyverno-policies

# Validate templates first
./validate-templates.sh

helm install trinet-policies . --namespace kyverno --create-namespace --timeout=10m --wait

# Enforce mode (block violations) instead of default Audit (report only)
helm upgrade trinet-policies . --namespace kyverno --set validationFailureAction=Enforce --timeout=10m --wait

# Optional: after a successful install, drop install-time kyverno.io/ignore so Kyverno validates policies on apply
helm upgrade trinet-policies . --namespace kyverno --set installation.ignoreOnInstall=false --timeout=10m --wait
```

`values.yaml` sets `validationFailureAction` (default `Audit`). It drives `spec.validationFailureAction` on `ClusterPolicy` resources. For `ValidatingPolicy` resources, `Enforce` maps to `validationActions: [Deny]` and `Audit` to `[Audit]`.

## Manual Cluster Test (Helm Install)

Use this flow to manually verify everything in a cluster before automating in GitOps.

```bash
cd kyverno-policies

# 1) Validate chart templates locally
./validate-templates.sh

# 2) Confirm target cluster and Kyverno are healthy
kubectl config current-context
kubectl get pods -n kyverno

# If you only have one admission-controller replica, scale up before installing many policies
# (reduces validate-policy webhook timeouts during helm install)
kubectl -n kyverno scale deploy kyverno-admission-controller --replicas=3
kubectl -n kyverno rollout status deploy/kyverno-admission-controller --timeout=180s

# 3) Install policies with Helm (Audit by default)
helm install trinet-policies . --namespace kyverno --timeout=10m --wait

# 4) Verify Helm release status
helm list -n kyverno

# 5) Verify policy readiness
kubectl get clusterpolicy -o custom-columns=NAME:.metadata.name,READY:.status.conditions[0].status,REASON:.status.conditions[0].reason
kubectl get validatingpolicy.policies.kyverno.io -o custom-columns=NAME:.metadata.name,READY:.status.conditionStatus.ready
```

Switch to enforce mode after validation:

```bash
helm upgrade trinet-policies . --namespace kyverno --set validationFailureAction=Enforce --timeout=10m --wait
```

Optional hardening step after a successful install:

```bash
helm upgrade trinet-policies . --namespace kyverno --set installation.ignoreOnInstall=false --timeout=10m --wait
```

Rollback / cleanup:

```bash
helm uninstall trinet-policies -n kyverno
```

## GitOps Integration

For GitOps, keep this chart as a separate app/release and deploy it only after Kyverno is ready.

- **Order**: sync/install Kyverno first, then this policy chart.
- **Default mode**: keep `validationFailureAction: Audit` in `values.yaml`.
- **Environment overrides**: set `validationFailureAction=Enforce` in production overlays/values.
- **Initial reliability**: keep `installation.ignoreOnInstall: true` for first reconciliation on large policy sets; optionally set it to `false` in a follow-up sync.
- **Admission capacity**: in the Kyverno Helm values (not this chart), set `admissionController.replicas` to at least **3** in non-trivial clusters so policy validation webhooks do not time out during sync.
- **Health checks**: include checks for `ClusterPolicy` and `ValidatingPolicy` readiness in your pipeline or post-sync hooks.

Example GitOps-friendly Helm command:

```bash
helm upgrade --install trinet-policies ./kyverno-policies \
  --namespace kyverno \
  --create-namespace \
  --timeout=10m \
  --wait
```

### Validation

Before installing, validate your templates:

```bash
cd kyverno-policies
./validate-templates.sh
```

This checks for:
- Missing `apiVersion` or `kind` fields
- Corrupted files (404 errors, etc.)
- Valid Helm template rendering

## Troubleshooting

### Webhook Timeout Issues

If you see errors like this while running `helm install` / `helm upgrade`:

```
failed calling webhook "validate-policy.kyverno.svc" ... policyvalidate?timeout=10s: context deadline exceeded
```

**What it means:** Kubernetes calls Kyverno’s **policy validation** admission webhook with a **10 second** timeout. Installing or upgrading **many** policies at once can exceed that limit if Kyverno admission is busy (often **one admission-controller replica** on a small cluster).

**Fix (try in order):**

1. **Scale Kyverno admission controller** (most effective), then retry Helm:

```bash
kubectl -n kyverno scale deploy kyverno-admission-controller --replicas=3
kubectl -n kyverno rollout status deploy/kyverno-admission-controller --timeout=180s
helm uninstall trinet-policies -n kyverno   # only if a failed/partial release exists
helm install trinet-policies . -n kyverno --timeout=10m --wait
```

2. **GitOps / permanent fix:** set `admissionController.replicas: 3` (or higher) in the **Kyverno** Helm chart values for that cluster.

3. **Optional:** raise the webhook `timeoutSeconds` toward the Kubernetes maximum (**30**). Kyverno may reconcile this value; if a patch does not stick, fix it in the Kyverno chart values instead of manual patches.

```bash
kubectl patch validatingwebhookconfiguration kyverno-policy-validating-webhook-cfg \
  --type='json' -p='[{"op": "replace", "path": "/webhooks/0/timeoutSeconds", "value": 30}]'
```

4. **Fallback (no Helm release):** apply rendered manifests with server-side apply (sequential, usually avoids the worst timeouts):

```bash
cd kyverno-policies
./install.sh
```

See also `./apply-policies.sh` if you use that workflow locally.

### Helm Ownership Errors

If you see "invalid ownership metadata" errors:

```
Error: ValidatingPolicy "disallow-capabilities-strict" exists and cannot be imported: 
invalid ownership metadata; missing key "app.kubernetes.io/managed-by"
```

**Quick Fix:**
```bash
./fix-helm-ownership.sh sample-policies kyverno
```

This adds the required Helm labels and annotations to existing policies.

### Other Common Issues

If you encounter errors like "apiVersion not set, kind not set", see [TROUBLESHOOTING.md](kyverno-policies/TROUBLESHOOTING.md) for solutions.

Common issues:
- **Wrong directory**: Make sure you're in `kyverno-policies/` not the repo root
- **Invalid template files**: Run `./validate-templates.sh` to find them
- **Corrupted files**: Check for files containing "404" or "Not Found"
- **Webhook timeouts**: Scale `kyverno-admission-controller` replicas, then retry Helm; or use `./install.sh` as a fallback

## Repository Structure

```
kyverno-helm-chart/
├── kyverno-policies/          # Helm chart directory
│   ├── Chart.yaml            # Chart metadata
│   ├── values.yaml           # Default values
│   ├── templates/            # Policy templates
│   ├── validate-templates.sh # Validation script
│   ├── install.sh            # helm template | kubectl apply (webhook timeout fallback)
│   ├── apply-policies.sh     # Legacy batch apply helper
│   └── TROUBLESHOOTING.md    # Troubleshooting guide
└── README.md                 # This file
```

## Related Repositories

- [Kyverno Policy Helm Chart](https://github.com/nirmata/kyverno-policy-helm-chart) - Reference implementation

