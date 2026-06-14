#!/bin/bash
FLUTTER_ROOT="${FLUTTER_ROOT:-/Users/benjamin/Development/flutter}"
ORIGINAL_BACKEND="$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh"
export PATH="/tmp/codesign_wrapper:$PATH"
"$ORIGINAL_BACKEND" "$@"
