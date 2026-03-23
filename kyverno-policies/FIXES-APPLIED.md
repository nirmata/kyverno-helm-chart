# Kyverno Expression Escaping - Fixes Applied

## Problem

Helm was trying to interpret Kyverno JMESPath expressions (like `{{ request.operation }}`, `{{ element() }}`) as Helm template functions, causing errors:

```
Error: parse error at (kyverno-policies/templates/require-drop-cap-net-raw.yaml:42): 
function "element" not defined
```

## Solution

All Kyverno JMESPath expressions have been escaped so Helm treats them as literal strings that will be processed by Kyverno at runtime.

**Escaping format:**
- Original: `{{ request.operation }}`
- Escaped: `{{ "{{" }} request.operation {{ "}}" }}`

When Helm renders the template, it outputs: `{{ request.operation }}` (which Kyverno can then process).

## Files Fixed

The following files had Kyverno expressions that needed escaping:

1. **require-drop-all-capabilities.yaml**
   - Fixed: `{{ request.operation || 'BACKGROUND' }}`
   - Fixed: `{{ element.securityContext.capabilities.drop[].to_upper(@) || `[]` }}`

2. **require-drop-cap-net-raw.yaml**
   - Fixed: `{{ element.securityContext.capabilities.drop[].to_upper(@) || `[]` }}`

3. **disallow-capabilities.yaml**
   - Fixed: `{{ `{{ request.object.spec.[ephemeralContainers, initContainers, containers][].securityContext.capabilities.add[] }}` }}`
   - (Was double-escaped, now correctly escaped)

4. **disallow-host-ports-range.yaml**
   - Fixed: `{{ request.object.spec.[ephemeralContainers, initContainers, containers][].ports[].hostPort }}`

5. **disallow_empty_ingress_host.yaml**
   - Fixed: `{{ request.object.spec.rules[].host || '[]' | length(@) }}`
   - Fixed: `{{ request.object.spec.rules[].http || '[]' | length(@) }}`
   - Removed `quote` function (not needed with proper escaping)

6. **restrict-volume-types.yaml**
   - Fixed: `{{ `{{ request.object.spec.volumes[].keys(@)[] || '' }}` }}`
   - (Was double-escaped, now correctly escaped)

7. **add-ttl-jobs.yaml**
   - Fixed: `{{ request.object.metadata.ownerReferences || `[]` }}`

8. **add-network-policy.yaml**
   - Fixed: `{{request.object.metadata.name}}`

9. **check-deprecated-apis.yaml**
   - Fixed: `{{ request.object.apiVersion }}` (2 occurrences)
   - Fixed: `{{ request.object.kind }}` (2 occurrences)

10. **check-evicted-pods.yaml**
    - Fixed: `{{ podphase }}`
    - Fixed: `{{poderror}}`
    - Fixed: `{{request.object.metadata.name}}`
    - Fixed: `{{request.namespace}}`

11. **check-ephmeral-storage-capacity.yaml**
    - Fixed: `{{request.object.metadata.name}}` (2 occurrences)
    - Fixed: `{{ nodeavailable }}`
    - Fixed: `{{ nodecapacity }}`
    - Fixed: `{{ availablecapacity }}`
    - Fixed: `{{ availablecappercent }}`
    - Fixed nested expressions in `round()` and `divide()` functions

12. **disallow-capabilities-strict.yaml**
    - Fixed: `{{ element.securityContext.capabilities.drop[] || `[]` }}`
    - Fixed: `{{ element.securityContext.capabilities.add[] || `[]` }}`

13. **check-deprecated-apis.yaml**
    - Removed: `admissionregistration.k8s.io/v1beta1/ValidatingWebhookConfiguration`
    - Removed: `admissionregistration.k8s.io/v1beta1/MutatingWebhookConfiguration`
    - Reason: These API versions were removed in Kubernetes 1.22+ and cannot be validated by Kyverno

## Verification

All templates now pass Helm validation:

```bash
helm template test .  # ✓ No parse errors
helm install policy . --namespace kyverno --dry-run  # ✓ Validates successfully
```

## How It Works

1. **Helm renders the template:**
   ```yaml
   value: "{{ "{{" }} request.operation {{ "}}" }}"
   ```
   
2. **Helm outputs:**
   ```yaml
   value: "{{ request.operation }}"
   ```

3. **Kyverno processes the policy:**
   - Kyverno sees `{{ request.operation }}` as a JMESPath expression
   - Evaluates it at runtime
   - Works correctly!

## Prevention

To prevent this issue in the future:

1. **Use the validation script:**
   ```bash
   ./validate-templates.sh
   ```

2. **Check for unescaped expressions:**
   ```bash
   grep -r "{{" templates/*.yaml | grep -v "{{- if\|{{- end\|{{ include\|{{ .\|{{ \"{{"
   ```

3. **Test before committing:**
   ```bash
   helm template test .
   ```

## Related Documentation

- See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for other common issues
- See [README.md](../README.md) for installation instructions

