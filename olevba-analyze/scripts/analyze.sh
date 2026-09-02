#!/usr/bin/env bash
# Analyze an Office file for VBA macros / suspicious content using oletools.
# Usage: analyze.sh <file-path>
set -euo pipefail

INPUT="${1:-}"
if [[ -z "$INPUT" ]]; then
  echo "ERROR: missing file path" >&2
  echo "Usage: $0 <file-path>" >&2
  exit 2
fi

ensure_olevba() {
  if command -v olevba >/dev/null 2>&1; then
    return 0
  fi
  if ! command -v pipx >/dev/null 2>&1; then
    echo "ERROR: olevba not found and pipx is not installed. Install oletools first." >&2
    exit 3
  fi
  echo "olevba not found; installing oletools via pipx..."
  pipx install oletools
}

resolve_path() {
  local raw="$1"
  if [[ -f "$raw" ]]; then
    printf '%s\n' "$raw"
    return 0
  fi

  local base
  base="$(basename -- "$raw")"
  # Word lock files are not the target.
  if [[ "$base" == '~$'* ]]; then
    echo "ERROR: path looks like a Word lock file: $raw" >&2
    return 1
  fi

  # Search by basename under the given parent, then common Agentflow roots.
  local parent
  parent="$(dirname -- "$raw")"
  local search_roots=()
  [[ -d "$parent" ]] && search_roots+=("$parent")
  [[ -d "$(dirname -- "$parent")" ]] && search_roots+=("$(dirname -- "$parent")")
  [[ -d /mnt/d/Agentflow ]] && search_roots+=("/mnt/d/Agentflow")

  local found=""
  local root
  for root in "${search_roots[@]}"; do
    found="$(find "$root" -type f \( -name "$base" -o -name "*${base}" \) ! -name '~$*' 2>/dev/null | head -n 5 || true)"
    if [[ -n "$found" ]]; then
      # Prefer exact basename match.
      local exact
      exact="$(printf '%s\n' "$found" | while IFS= read -r p; do
        [[ "$(basename -- "$p")" == "$base" ]] && printf '%s\n' "$p"
      done | head -n 1)"
      if [[ -n "$exact" ]]; then
        printf '%s\n' "$exact"
        return 0
      fi
      printf '%s\n' "$(printf '%s\n' "$found" | head -n 1)"
      return 0
    fi
  done

  echo "ERROR: file not found: $raw" >&2
  if [[ -d "$parent" ]]; then
    echo "Parent directory listing:" >&2
    ls -1 "$parent" >&2 || true
  fi
  return 1
}

ensure_olevba
FILE="$(resolve_path "$INPUT")" || exit 1

echo "===== TARGET ====="
echo "input: $INPUT"
echo "resolved: $FILE"
ls -l -- "$FILE"
echo
file -- "$FILE" || true
echo

run_tool() {
  local title="$1"
  shift
  echo "===== ${title} ====="
  if command -v "$1" >/dev/null 2>&1; then
    "$@" || true
  else
    echo "(skipped: $1 not installed)"
  fi
  echo
}

run_tool "OLEVBA" olevba -- "$FILE"
run_tool "OLEID" oleid -- "$FILE"
run_tool "MRAPTOR" mraptor -- "$FILE"
run_tool "OLEOBJ" oleobj -- "$FILE"
run_tool "OLEDIR" oledir -- "$FILE"
