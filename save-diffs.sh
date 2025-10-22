#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   save-diffs.sh [base_ref] [target_ref]
# Defaults:
#   base_ref: master
#   target_ref: HEAD
#
# Notes:
# - Uses triple-dot (base...target) to show changes on the current branch vs base.
# - Prints absolute filenames of saved diffs (one per line).
# - For binary changes, added/deleted are recorded as 0-0.
# - Writes .diff files next to each source file (creates directories as needed).

BASE_REF="${1:-master}"
TARGET_REF="${2:-HEAD}"
DIFF_RANGE="${BASE_REF}...${TARGET_REF}"

# Ensure we're inside a git repo
git_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${git_root}" ]]; then
  echo "Error: not inside a git repository." >&2
  exit 1
fi

# If local base ref doesn't exist, try origin/base
if ! git rev-parse --verify --quiet "${BASE_REF}" >/dev/null; then
  if git rev-parse --verify --quiet "origin/${BASE_REF}" >/dev/null; then
    BASE_REF="origin/${BASE_REF}"
    DIFF_RANGE="${BASE_REF}...${TARGET_REF}"
  fi
fi

# If nothing changed, exit quietly
if git diff --quiet "${DIFF_RANGE}" --diff-filter=ACDMRTUXB; then
  exit 0
fi

# Iterate changed files robustly (-z for NUL-separated)
# Include Added/Copied/Deleted/Modified/Renamed/Type/Unmerged/Unknown/Binary
while IFS= read -r -d '' file_path; do
  # Compute added/deleted counts for this file
  added="0"
  deleted="0"
  # numstat returns: <added>\t<deleted>\t<path>
  # For binary files numstat prints '-' for counts; map to 0
  if num_line="$(git diff --numstat "${DIFF_RANGE}" -- "$file_path" | head -n1)"; then
    a="$(printf '%s' "$num_line" | awk -F'\t' '{print $1}')"
    d="$(printf '%s' "$num_line" | awk -F'\t' '{print $2}')"
    [[ "$a" != "-" ]] && added="$a" || added="0"
    [[ "$d" != "-" ]] && deleted="$d" || deleted="0"
  fi

  src_dir="$(dirname "$file_path")"
  src_base="$(basename "$file_path")"
  out_dir="${git_root}/${src_dir}"
  mkdir -p "$out_dir"

  out_file="${out_dir}/${src_base}.${added}-${deleted}.diff"

  # Save the per-file diff (no color codes)
  git diff --no-color "${DIFF_RANGE}" -- "$file_path" > "$out_file"

  # Print the saved diff filename
  printf '%s\n' "$out_file"
done < <(git diff --name-only -z "${DIFF_RANGE}" --diff-filter=ACDMRTUXB)


