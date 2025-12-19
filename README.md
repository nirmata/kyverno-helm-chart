# Kyverno Policies Helm Chart

Helm chart for deploying Kyverno policies to Kubernetes clusters.

## Quick Start

### Prerequisites

- Kubernetes cluster with Kyverno installed
- Helm 3.x
- kubectl configured for your cluster

### Installation

**Important**: Always run Helm commands from the `kyverno-policies` directory:

```bash
cd kyverno-policies

# Validate templates first
./validate-templates.sh

# Install with default values (Audit mode)
helm install trinet-policies . --namespace kyverno --create-namespace

# Or with custom values
helm install trinet-policies . \
  --namespace kyverno \
  --create-namespace \
  --set validationFailureAction=Enforce
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

If you see webhook timeout errors when installing:

```
Error: failed calling webhook "validate-policy.kyverno.svc": context deadline exceeded
```

**Quick Fix - Use Batch Script (Recommended):**
```bash
cd kyverno-policies
./apply-policies.sh
```

**Alternative - Increase Timeout:**
```bash
# Increase webhook timeout
kubectl patch validatingwebhookconfiguration kyverno-policy-validating-webhook-cfg \
  --type='json' -p='[{"op": "replace", "path": "/webhooks/0/timeoutSeconds", "value": 30}]'

# Then retry
helm install trinet-policies . --namespace kyverno --timeout 10m
```

**Alternative - Apply Directly:**
```bash
helm template trinet-policies . --namespace kyverno > /tmp/policies.yaml
kubectl apply -f /tmp/policies.yaml --server-side --force-conflicts
```

### Helm Ownership Errors

If you see "invalid ownership metadata" errors:

```
Error: ValidatingPolicy "disallow-capabilities-strict" exists and cannot be imported: 
invalid ownership metadata; missing key "app.kubernetes.io/managed-by"
```

**Quick Fix:**
```bash
./fix-helm-ownership.sh trinet-policies kyverno
```

This adds the required Helm labels and annotations to existing policies.

### Other Common Issues

If you encounter errors like "apiVersion not set, kind not set", see [TROUBLESHOOTING.md](kyverno-policies/TROUBLESHOOTING.md) for solutions.

Common issues:
- **Wrong directory**: Make sure you're in `kyverno-policies/` not the repo root
- **Invalid template files**: Run `./validate-templates.sh` to find them
- **Corrupted files**: Check for files containing "404" or "Not Found"
- **Webhook timeouts**: Use `./apply-policies.sh` or increase timeout first

## Repository Structure

```
kyverno-helm-chart/
├── kyverno-policies/          # Helm chart directory
│   ├── Chart.yaml            # Chart metadata
│   ├── values.yaml           # Default values
│   ├── templates/            # Policy templates
│   ├── validate-templates.sh # Validation script
│   ├── apply-policies.sh     # Batch application script (for webhook timeouts)
│   └── TROUBLESHOOTING.md    # Troubleshooting guide
└── README.md                 # This file
```

## Related Repositories

- [TriNet Private Repo](../trinet-private-repo) - Complete Helm chart with template generation
- [Kyverno Policy Helm Chart](https://github.com/nirmata/kyverno-policy-helm-chart) - Reference implementation

