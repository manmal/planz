#!/bin/bash
# Lint Zig source files
# Rules:
#   - No file longer than 300 lines
#   - Run zig fmt check

set -e

MAX_LINES=300
ERRORS=0

echo "Checking line counts (max $MAX_LINES)..."
for file in $(find src -name "*.zig"); do
    lines=$(wc -l < "$file")
    if [ "$lines" -gt "$MAX_LINES" ]; then
        echo "ERROR: $file has $lines lines (max: $MAX_LINES)"
        ERRORS=$((ERRORS + 1))
    else
        echo "  OK: $file ($lines lines)"
    fi
done

echo ""
echo "Checking zig fmt..."
if ! zig fmt --check src/; then
    echo "ERROR: Code is not formatted. Run: zig fmt src/"
    ERRORS=$((ERRORS + 1))
fi

if [ "$ERRORS" -gt 0 ]; then
    echo ""
    echo "FAILED: $ERRORS error(s) found"
    exit 1
fi

echo ""
echo "All checks passed!"
