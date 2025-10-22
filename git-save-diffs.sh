#!/usr/bin/env bash
set -euo pipefail

# save-commit-diffs.sh
# Splits the current commit's diff into per-hunk files saved next to source files.
# Filenames follow: source_filename.START-END.diff where START-END is the changed
# line range in the source (using new-file line numbers, or old-file for deletions).
#
# Diff target selection:
# - If this is the first commit on the branch (ahead-of-merge-base == 1), diff is HEAD vs master/main head
# - Otherwise, diff is HEAD^ vs HEAD (current commit vs its parent)
#
# Output: prints each saved diff file path, one per line

repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [[ -z "${repo_root}" ]]; then
  echo "Error: not inside a git repository" >&2
  exit 1
fi

cd "${repo_root}"

default_main_branch() {
  # Prefer local master/main, else fallback to origin/* if local not present
  if git show-ref --verify --quiet refs/heads/master; then
    echo master
    return
  fi
  if git show-ref --verify --quiet refs/heads/main; then
    echo main
    return
  fi
  if git show-ref --verify --quiet refs/remotes/origin/master; then
    echo origin/master
    return
  fi
  if git show-ref --verify --quiet refs/remotes/origin/main; then
    echo origin/main
    return
  fi
  # Fallback
  echo master
}

base_branch=$(default_main_branch)
merge_base=$(git merge-base HEAD "${base_branch}")
ahead_count=$(git rev-list --count "${merge_base}"..HEAD)

left_ref=""
right_ref="HEAD"
if [[ "${ahead_count}" == "1" ]]; then
  # First commit on branch: compare branch head to master/main head
  left_ref="${base_branch}"
else
  # Compare current commit to its immediate parent
  left_ref="HEAD^"
fi

# Generate a unified diff with zero context for precise hunk ranges
# Include file operations we care about; exclude binary diffs from content but keep headers
diff_output=$(git diff --unified=0 --no-color --no-ext-diff --diff-filter=ACDMRTUXB "${left_ref}" "${right_ref}" || true)

# If no diff, exit quietly
if [[ -z "${diff_output}" ]]; then
  exit 0
fi

# Parse diff and write per-hunk files
awk -v repo_root="${repo_root}" '
  function trim_prefix(path,   p) {
    p = path
    sub(/^a\//, "", p)
    sub(/^b\//, "", p)
    return p
  }

  function parse_range(spec, arr,   m) {
    # spec like "+123,4" or "-7" (count defaults to 1)
    if (match(spec, /([+-])([0-9]+)(,([0-9]+))?/, m)) {
      arr["sign"] = m[1]
      arr["start"] = m[2] + 0
      arr["count"] = (m[4] != "" ? m[4] + 0 : 1)
      return 1
    }
    return 0
  }

  function start_hunk_file(old_path, new_path, old_spec, new_spec,   oldR, newR, target_path, disp_start, disp_end, clean_new, clean_old, dir, base, out_path) {
    # Determine display range and target source path
    parse_range(old_spec, oldR)
    parse_range(new_spec, newR)

    clean_new = (new_path == "/dev/null" ? "" : trim_prefix(new_path))
    clean_old = (old_path == "/dev/null" ? "" : trim_prefix(old_path))

    if (newR["count"] > 0 && clean_new != "") {
      disp_start = newR["start"]
      disp_end   = newR["start"] + newR["count"] - 1
      target_path = clean_new
    } else {
      # Pure deletion or no new lines: use old range
      disp_start = oldR["start"]
      disp_end   = oldR["start"] + oldR["count"] - 1
      target_path = (clean_old != "" ? clean_old : clean_new)
    }

    if (target_path == "") {
      # Nothing to do
      writing = 0
      return
    }

    # Compute output file path near the source file
    # out_path = dirname(target_path) + "/" + basename(target_path) + ".START-END.diff"
    dir = target_path
    base = target_path
    sub(/^(.*)\/(.+)$/, "\\1", dir)
    if (dir == base) { dir = "." } # file in repo root
    sub(/^.*\//, "", base)

    out_path = repo_root "/" dir "/" base "." disp_start "-" disp_end ".diff"

    # Open new file for writing
    close(current_out)
    current_out = out_path
    print current_out

    # Write minimal headers for context
    print "--- " old_path > current_out
    print "+++ " new_path > current_out
    print current_hunk_header > current_out
    writing = 1
  }

  BEGIN {
    current_out = ""
    writing = 0
    old_path = ""
    new_path = ""
    current_hunk_header = ""
  }

  /^diff --git / {
    # New file section; reset paths and stop writing to previous hunk file
    writing = 0
    old_path = ""
    new_path = ""
    next
  }

  /^--- / {
    old_path = $2
    next
  }

  /^\+\+\+ / {
    new_path = $2
    next
  }

  /^@@ / {
    # Hunk header like: @@ -oldStart,oldCount +newStart,newCount @@
    current_hunk_header = $0
    # Extract range specs (fields 2 and 3)
    # Example tokens: "@@", "-12,3", "+15,2", "@@"
    old_spec = $2
    new_spec = $3
    start_hunk_file(old_path, new_path, old_spec, new_spec)
    next
  }

  {
    if (writing) {
      # Write hunk body lines until next hunk/file header
      print $0 > current_out
    }
  }
' <<< "${diff_output}" | tee /dev/stderr | grep -E '\.diff$' || true

# Note: The awk prints each created filename to stdout before writing the hunk.
# The tee to stderr lets users see progress while preserving stdout as the list of files.


