#!/usr/bin/env bash
set -euo pipefail

# Save per-file diffs for the current commit. If this is the first commit on the branch,
# diff against default branch head (master/main/origin default). Otherwise, diff against previous commit.
# Output: prints the saved diff filenames, one per line.

# Flags
VERBOSE=false
while getopts ":v" opt; do
  case "$opt" in
    v) VERBOSE=true ;;
    *) : ;;
  esac
done

log() { $VERBOSE && printf "%s\n" "$*" >&2 || :; }

# Ensure we are inside a git repo
if ! REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
  printf "Not a git repository: %s\n" "$(pwd)" >&2
  exit 0
fi
cd "$REPO_ROOT"
log "Repo root: $REPO_ROOT"

current_commit=$(git rev-parse HEAD)
current_branch=$(git rev-parse --abbrev-ref HEAD)
log "Current commit: $current_commit"
log "Current branch: $current_branch"

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

# Try to resolve default branch, but do not exit if unavailable
default_branch=""
if resolved=$(resolve_default_branch); then
  default_branch="$resolved"
fi
log "Default branch: ${default_branch:-<none>}"

# Are we on the default branch? Normalize names to compare
simplified_default=${default_branch##*/}
on_default_branch=false
if [[ "$current_branch" == "$simplified_default" ]]; then
  on_default_branch=true
fi
log "On default branch? $on_default_branch"

# Find merge-base with default branch and count commits since base
commits_since_base=0
if [[ -n "$default_branch" ]]; then
  merge_base=$(git merge-base "$current_commit" "$default_branch")
  commits_since_base=$(git rev-list --count "$merge_base..$current_commit")
fi
log "Commits since base: $commits_since_base"

# Choose diff base
# Helper: determine if current commit has a parent
if git rev-parse --verify -q "$current_commit^" >/dev/null; then
  has_parent=true
else
  has_parent=false
fi

# Helper: empty tree for initial commit diffs
empty_tree=$(git hash-object -t tree /dev/null)

# Choose diff base without exiting on missing default branch
if $on_default_branch; then
  if $has_parent; then
    diff_base="$current_commit^"
  else
    diff_base="$empty_tree"
  fi
else
  if [[ -n "$default_branch" && "$commits_since_base" -le 1 ]]; then
    diff_base=$(git rev-parse "$default_branch")
  else
    if $has_parent; then
      diff_base="$current_commit^"
    else
      diff_base="$empty_tree"
    fi
  fi
fi
log "Diff base: $diff_base"

# Get changed files (portable, avoids mapfile)
changed_files=()
while IFS= read -r path; do
  if [[ -n "$path" ]]; then
    changed_files+=("$path")
  fi
done < <(git diff --name-only "$diff_base" "$current_commit")
log "Changed files count: ${#changed_files[@]}"

if [[ ${#changed_files[@]} -eq 0 ]]; then
  log "No changes detected."
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
    log "Empty diff for $path, skipping"
    continue
  fi
  created_files+=("$out_file")
  log "Created: $out_file"

done

for f in "${created_files[@]}"; do
  printf "%s\n" "$f"
done


