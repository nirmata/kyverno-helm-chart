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

If you encounter errors like "apiVersion not set, kind not set", see [TROUBLESHOOTING.md](kyverno-policies/TROUBLESHOOTING.md) for solutions.

Common issues:
- **Wrong directory**: Make sure you're in `kyverno-policies/` not the repo root
- **Invalid template files**: Run `./validate-templates.sh` to find them
- **Corrupted files**: Check for files containing "404" or "Not Found"

## Repository Structure

```
kyverno-helm-chart/
├── kyverno-policies/          # Helm chart directory
│   ├── Chart.yaml            # Chart metadata
│   ├── values.yaml           # Default values
│   ├── templates/            # Policy templates
│   ├── validate-templates.sh # Validation script
│   └── TROUBLESHOOTING.md    # Troubleshooting guide
└── README.md                 # This file
```

## Related Repositories

- [TriNet Private Repo](../trinet-private-repo) - Complete Helm chart with template generation
- [Kyverno Policy Helm Chart](https://github.com/nirmata/kyverno-policy-helm-chart) - Reference implementation

