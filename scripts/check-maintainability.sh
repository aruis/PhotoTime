#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[maintainability] checking debt markers..."
if rg -n --hidden --glob '!.git/**' --glob '!.derivedData/**' --glob '!*.xcresult/**' \
  '\b(TODO|FIXME|HACK|XXX)\b' \
  PhotoTime PhotoTimeTests PhotoTimeUITests; then
  echo "[maintainability] ERROR: debt markers detected. Please resolve or track via explicit issue process."
  exit 1
fi

echo "[maintainability] checking core file size budgets..."
content_view_lines="$(wc -l < PhotoTime/ContentView.swift | tr -d ' ')"
export_vm_export_lines="$(wc -l < PhotoTime/ExportViewModel+Export.swift | tr -d ' ')"

if [[ "$content_view_lines" -gt 700 ]]; then
  echo "[maintainability] ERROR: PhotoTime/ContentView.swift is too large (${content_view_lines} > 700)."
  exit 1
fi

if [[ "$export_vm_export_lines" -gt 850 ]]; then
  echo "[maintainability] ERROR: PhotoTime/ExportViewModel+Export.swift is too large (${export_vm_export_lines} > 850)."
  exit 1
fi

echo "[maintainability] PASSED"
