# Troubleshooting Guide

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

