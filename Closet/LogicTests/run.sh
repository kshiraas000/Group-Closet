#!/bin/bash
# The Xcode project has no test target, so the pure (Foundation-only) logic is
# compiled together with these assertion tests and run as a plain executable.
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(mktemp -d)/logic-tests"
xcrun swiftc -o "$out" \
  Closet/Models/Item.swift \
  Closet/Selection/GridSelection.swift \
  Closet/Selection/BulkEdit.swift \
  LogicTests/main.swift
"$out"
