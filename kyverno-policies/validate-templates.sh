#!/bin/bash
# Script to validate Helm chart templates
# Checks for files missing apiVersion and kind

set -e

CHART_DIR="${1:-.}"

echo "Validating Helm chart templates in: $CHART_DIR"
echo "=============================================="
echo ""

INVALID_FILES=()
TEMPLATE_DIR="$CHART_DIR/templates"

if [ ! -d "$TEMPLATE_DIR" ]; then
  echo "Error: templates directory not found in $CHART_DIR"
  exit 1
fi

# Check each YAML file in templates
for file in "$TEMPLATE_DIR"/*.yaml "$TEMPLATE_DIR"/*.yml; do
  # Skip if no files match
  [ -f "$file" ] || continue
  
  filename=$(basename "$file")
  
  # Skip NOTES.txt and _helpers.tpl
  if [[ "$filename" == "NOTES.txt" ]] || [[ "$filename" == "_helpers.tpl" ]]; then
    continue
  fi
  
  # Check if file has apiVersion
  if ! grep -q "^apiVersion:" "$file" 2>/dev/null; then
    echo "✗ Invalid: $filename (missing apiVersion)"
    echo "  Content preview:"
    head -3 "$file" | sed 's/^/    /'
    INVALID_FILES+=("$file")
    continue
  fi
  
  # Check if file has kind
  if ! grep -q "^kind:" "$file" 2>/dev/null; then
    echo "✗ Invalid: $filename (missing kind)"
    echo "  Content preview:"
    head -5 "$file" | sed 's/^/    /'
    INVALID_FILES+=("$file")
    continue
  fi
  
  # Check for common error patterns
  if grep -qi "404\|not found\|error" "$file" 2>/dev/null; then
    echo "⚠ Warning: $filename (contains error patterns)"
    grep -i "404\|not found\|error" "$file" | head -2 | sed 's/^/    /'
  fi
  
  echo "✓ Valid: $filename"
done

echo ""
if [ ${#INVALID_FILES[@]} -eq 0 ]; then
  echo "✓ All template files are valid!"
  echo ""
  echo "Testing Helm template rendering..."
  if helm template test "$CHART_DIR" > /dev/null 2>&1; then
    echo "✓ Helm template rendering successful!"
    exit 0
  else
    echo "✗ Helm template rendering failed"
    helm template test "$CHART_DIR" 2>&1 | head -20
    exit 1
  fi
else
  echo "✗ Found ${#INVALID_FILES[@]} invalid file(s):"
  for file in "${INVALID_FILES[@]}"; do
    echo "  - $file"
  done
  echo ""
  echo "Please fix or remove these files before installing the chart."
  exit 1
fi

