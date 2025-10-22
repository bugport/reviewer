#!/usr/bin/env bash

set -euo pipefail

# git-save-diffs.sh
#
# Generates per-hunk diff files for the current commit relative to:
# - master/main HEAD if this is the first commit on the branch since diverging
# - otherwise the immediate parent commit (HEAD~1)
#
# For each changed source file, creates one or more files placed next to the
# source file, named like: <source_filename>.<start>-<end>.diff, where <start>
# and <end> are the line numbers on the new file side for each changed hunk.
#
# Outputs the paths of the created diff files, one per line.

repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "${repo_root}" ]; then
  echo "Error: Not inside a git repository." >&2
  exit 1
fi

cd "${repo_root}"

# Determine upstream default branch: prefer master, then main, then origin/*
find_upstream_branch() {
  local candidates=("master" "main" "origin/master" "origin/main")
  local c
  for c in "${candidates[@]}"; do
    if git rev-parse --verify --quiet "$c" >/dev/null; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

UPSTREAM=$(find_upstream_branch || true)
if [ -z "${UPSTREAM}" ]; then
  echo "Error: Could not find an upstream branch (master/main)." >&2
  exit 1
fi

# Identify base commit according to the rules
MERGE_BASE=$(git merge-base HEAD "${UPSTREAM}")
COMMITS_SINCE_BASE=$(git rev-list --count "${MERGE_BASE}..HEAD")

if [ "${COMMITS_SINCE_BASE}" -eq 1 ]; then
  BASE_REF="${UPSTREAM}"
else
  BASE_REF="HEAD~1"
fi

# Collect changed files (Added or Modified). Exclude deletions and others.
mapfile -t changed_files < <(git diff --name-only --diff-filter=AM "${BASE_REF}..HEAD")

# If nothing changed, exit quietly
if [ ${#changed_files[@]} -eq 0 ]; then
  exit 0
fi

# Temporary file for collecting output filenames
out_list=$(mktemp)
trap 'rm -f "${out_list}"' EXIT

# For each file, split its diff into per-hunk files
for f in "${changed_files[@]}"; do
  # Ensure directory exists (it should, as we place files next to sources)
  dir=$(dirname -- "$f")
  base=$(basename -- "$f")

  # Generate zero-context diff to get precise hunk ranges; skip binaries
  # shellcheck disable=SC2016
  git diff -U0 "${BASE_REF}..HEAD" -- "$f" | \
  awk -v fpath="$f" -v out_list_file="${out_list}" '
    BEGIN {
      idx=""; oldh=""; newh="";
      in_hunk=0; skip=0;
      ofile="";
    }

    /^Binary files / {
      # Skip binary diffs entirely
      next
    }

    /^diff --git / {
      # Start of file diff header
      file_header=$0 "\n";
      next
    }

    /^index / {
      idx=$0 "\n"; next
    }

    /^--- / {
      oldh=$0 "\n"; next
    }

    /^\+\+\+ / {
      newh=$0 "\n"; next
    }

    /^@@ / {
      # New hunk: determine +start,len from header
      in_hunk=1; skip=0;
      # Extract +start,len (len optional defaults to 1)
      if (match($0, /\+([0-9]+),?([0-9]*)/, m)) {
        start=m[1]; len=(m[2]==""?1:m[2]);
      } else {
        # If cannot parse, skip this hunk
        skip=1;
      }

      # If len==0, this hunk only deletes lines in new file; skip per requirement
      if (len==0) { skip=1; }

      if (!skip) {
        end=start+len-1;
        ofile=sprintf("%s.%d-%d.diff", fpath, start, end);

        # Write a minimal valid header for the single-hunk diff
        print "diff --git a/" fpath " b/" fpath > ofile;
        if (idx != "") { printf "%s", idx > ofile }
        if (oldh != "") { printf "%s", oldh > ofile }
        if (newh != "") { printf "%s", newh > ofile }
        print $0 > ofile;

        # Record the created filename
        print ofile >> out_list_file;
      }
      next
    }

    {
      # Regular diff content lines; append to current hunk file if not skipping
      if (in_hunk && !skip && ofile != "") {
        print $0 >> ofile;
      }
      next
    }
  '
done

# Output the list of created diff filenames (one per line)
if [ -s "${out_list}" ]; then
  sort -u "${out_list}"
fi

exit 0


