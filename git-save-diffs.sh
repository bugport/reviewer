#!/usr/bin/env bash
set -euo pipefail

# Save per-file diffs for the current commit. If this is the first commit on the branch,
# diff against default branch head (master/main/origin default). Otherwise, diff against previous commit.
# Output: prints the saved diff filenames, one per line.

# Ensure we are inside a git repo
REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

current_commit=$(git rev-parse HEAD)
current_branch=$(git rev-parse --abbrev-ref HEAD)

# Determine default branch (prefer local master/main, else remote master/main, else origin/HEAD)
resolve_default_branch() {
  if git show-ref --verify --quiet refs/heads/master; then
    echo "master"; return 0
  fi
  if git show-ref --verify --quiet refs/heads/main; then
    echo "main"; return 0
  fi
  if git show-ref --verify --quiet refs/remotes/origin/master; then
    echo "origin/master"; return 0
  fi
  if git show-ref --verify --quiet refs/remotes/origin/main; then
    echo "origin/main"; return 0
  fi
  if ref=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null); then
    echo "$ref"; return 0
  fi
  return 1
}

if ! default_branch=$(resolve_default_branch); then
  echo "Could not determine default branch (master/main/origin HEAD)." >&2
  exit 1
fi

# Are we on the default branch? Normalize names to compare
simplified_default=${default_branch##*/}
on_default_branch=false
if [[ "$current_branch" == "$simplified_default" ]]; then
  on_default_branch=true
fi

# Find merge-base with default branch and count commits since base
merge_base=$(git merge-base "$current_commit" "$default_branch")
commits_since_base=$(git rev-list --count "$merge_base..$current_commit")

# Choose diff base
if $on_default_branch; then
  diff_base="$current_commit^"
else
  if [[ "$commits_since_base" -le 1 ]]; then
    diff_base=$(git rev-parse "$default_branch")
  else
    diff_base="$current_commit^"
  fi
fi

# Get changed files (portable, avoids mapfile)
changed_files=()
while IFS= read -r path; do
  if [[ -n "$path" ]]; then
    changed_files+=("$path")
  fi
done < <(git diff --name-only "$diff_base" "$current_commit")

if [[ ${#changed_files[@]} -eq 0 ]]; then
  exit 0
fi

created_files=()

for path in "${changed_files[@]}"; do
  added=0
  deleted=0
  if line=$(git diff --numstat "$diff_base" "$current_commit" -- "$path" | head -n1); then
    a=${line%%$'\t'*}; rest=${line#*$'\t'}; d=${rest%%$'\t'*}
    if [[ "$a" != "-" ]]; then added=$a; fi
    if [[ "$d" != "-" ]]; then deleted=$d; fi
  fi

  dir=$(dirname "$path")
  base=$(basename "$path")
  suffix="${added}-${deleted}.diff"
  target_dir="$dir"
  if [[ ! -d "$target_dir" ]]; then
    target_dir="."
  fi
  out_file="$target_dir/${base}.${suffix}"

  mkdir -p "$target_dir"
  git diff "$diff_base" "$current_commit" -- "$path" > "$out_file" || true
  if [[ ! -s "$out_file" ]]; then
    rm -f "$out_file"
    continue
  fi
  created_files+=("$out_file")

done

for f in "${created_files[@]}"; do
  printf "%s\n" "$f"
done


