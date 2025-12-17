#!/bin/bash
# Script to escape Kyverno JMESPath expressions in Helm templates
# This prevents Helm from trying to interpret them as template functions

set -e

TEMPLATES_DIR="templates"

if [ ! -d "$TEMPLATES_DIR" ]; then
  echo "Error: templates directory not found"
  exit 1
fi

echo "Escaping Kyverno JMESPath expressions in templates..."
echo "====================================================="
echo ""

FIXED_COUNT=0

# Function to escape Kyverno expressions in a file
escape_file() {
  local file=$1
  local temp_file=$(mktemp)
  local changed=false
  
  # Read file line by line
  while IFS= read -r line; do
    # Check if line contains unescaped Kyverno expressions
    # Pattern: {{ followed by request, element, poderror, nodeavailable, etc. (not Helm template syntax)
    if echo "$line" | grep -qE '\{\{[^}]*\b(request|element|poderror|nodeavailable|nodecapacity|availablecappercent|availablecapacity|podphase)\b[^}]*\}\}'; then
      # Escape the Kyverno expression
      escaped_line=$(echo "$line" | sed 's/{{/{{ "{{" }}/g' | sed 's/}}/{{ "}}" }}/g')
      echo "$escaped_line"
      changed=true
    else
      echo "$line"
    fi
  done < "$file" > "$temp_file"
  
  if [ "$changed" = true ]; then
    mv "$temp_file" "$file"
    return 0
  else
    rm "$temp_file"
    return 1
  fi
}

# Process each template file
for file in "$TEMPLATES_DIR"/*.yaml; do
  [ -f "$file" ] || continue
  
  filename=$(basename "$file")
  
  # Skip NOTES.txt and _helpers.tpl
  if [[ "$filename" == "NOTES.txt" ]] || [[ "$filename" == "_helpers.tpl" ]]; then
    continue
  fi
  
  # Check if file has unescaped Kyverno expressions
  if grep -qE '\{\{[^}]*\b(request|element|poderror|nodeavailable|nodecapacity|availablecappercent|availablecapacity|podphase)\b[^}]*\}\}' "$file" 2>/dev/null; then
    echo -n "Fixing $filename... "
    if escape_file "$file"; then
      echo "✓"
      FIXED_COUNT=$((FIXED_COUNT + 1))
    else
      echo "✗"
    fi
  fi
done

echo ""
if [ $FIXED_COUNT -gt 0 ]; then
  echo "✓ Fixed $FIXED_COUNT file(s)"
  echo ""
  echo "Testing Helm template rendering..."
  if helm template test . > /dev/null 2>&1; then
    echo "✓ Helm template rendering successful!"
  else
    echo "✗ Helm template rendering still has errors"
    helm template test . 2>&1 | head -20
    exit 1
  fi
else
  echo "✓ No files needed fixing (or all expressions already escaped)"
fi

