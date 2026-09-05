#!/usr/bin/env bash
set -euo pipefail

# Source the main script to test diff_by_key
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$script_dir/gh-pr-monitor"

tests_passed=0
tests_failed=0

# Helper to assert
assert_equal() {
  if [[ "$1" == "$2" ]]; then
    ((tests_passed++)) || true
  else
    echo "FAIL: $3" >&2
    echo "  Expected: $1" >&2
    echo "  Actual: $2" >&2
    ((tests_failed++)) || true
  fi
}

# Test 1: new items returned
diff=$(diff_by_key '[]' '[{"id":1,"body":"a"},{"id":2,"body":"b"}]' "id")
count=$(jq 'length' <<<"$diff")
assert_equal "2" "$count" "Test 1"

# Test 2: only new items returned
diff=$(diff_by_key '[{"id":1,"body":"a"}]' '[{"id":1,"body":"a"},{"id":2,"body":"b"}]' "id")
ids=$(jq -c 'map(.id) | sort' <<<"$diff")
assert_equal "[2]" "$ids" "Test 2"

# Test 3: changed items returned
diff=$(diff_by_key '[{"id":1,"body":"a"}]' '[{"id":1,"body":"EDITED"}]' "id")
body=$(jq -r '.[0].body' <<<"$diff")
assert_equal "EDITED" "$body" "Test 3"

# Test 4: empty
diff=$(diff_by_key '[]' '[]' "id")
assert_equal "[]" "$diff" "Test 4"

# Test 5: all unchanged
diff=$(diff_by_key '[{"id":1,"body":"a"},{"id":2,"body":"b"}]' '[{"id":1,"body":"a"},{"id":2,"body":"b"}]' "id")
assert_equal "[]" "$diff" "Test 5"

# Test 6: item removed
diff=$(diff_by_key '[{"id":1,"body":"a"},{"id":2,"body":"b"}]' '[{"id":1,"body":"a"}]' "id")
assert_equal "[]" "$diff" "Test 6"

# Test 7: multiple changes
diff=$(diff_by_key '[{"id":1,"body":"a"},{"id":2,"body":"b"}]' '[{"id":1,"body":"a"},{"id":2,"body":"EDITED"},{"id":3,"body":"c"}]' "id")
ids=$(jq -c 'map(.id) | sort' <<<"$diff")
assert_equal "[2,3]" "$ids" "Test 7"

# Test 8: check_mergeable treats a null statusCheckRollup (no CI configured) as passing
if check_mergeable '{"reviewDecision":"APPROVED","mergeStateStatus":"CLEAN","statusCheckRollup":null}'; then
  result="pass"
else
  result="block"
fi
assert_equal "pass" "$result" "Test 8: null statusCheckRollup"

# Test 9: check_mergeable treats NEUTRAL as non-blocking (GitHub's own semantics)
if check_mergeable '{"reviewDecision":"APPROVED","mergeStateStatus":"CLEAN","statusCheckRollup":[{"conclusion":"NEUTRAL","status":"COMPLETED"}]}'; then
  result="pass"
else
  result="block"
fi
assert_equal "pass" "$result" "Test 9: NEUTRAL conclusion"

# Test 10: check_mergeable blocks on TIMED_OUT (a conclusion an allowlist-of-failures would miss)
if check_mergeable '{"reviewDecision":"APPROVED","mergeStateStatus":"CLEAN","statusCheckRollup":[{"conclusion":"TIMED_OUT","status":"COMPLETED"}]}'; then
  result="pass"
else
  result="block"
fi
assert_equal "block" "$result" "Test 10: TIMED_OUT conclusion"

# Test 11: check_mergeable blocks on a still-running check
if check_mergeable '{"reviewDecision":"APPROVED","mergeStateStatus":"CLEAN","statusCheckRollup":[{"conclusion":null,"status":"IN_PROGRESS"}]}'; then
  result="pass"
else
  result="block"
fi
assert_equal "block" "$result" "Test 11: in-progress check"

# Test 12: two check runs sharing a name (routine for reruns/matrix jobs) must not be
# reported as "changed" every poll when nothing actually changed — regression test for
# the diff_by_key key-collapse bug, using detailsUrl (unique per run) as the key.
checks='[{"name":"build","detailsUrl":"u1","conclusion":"SUCCESS"},{"name":"build","detailsUrl":"u2","conclusion":"SKIPPED"}]'
normalized_prev=$(jq -c 'map(. + {id: (.detailsUrl // .targetUrl // .name // .context // (.|@json))})' <<<"$checks")
normalized_curr=$(jq -c 'map(. + {id: (.detailsUrl // .targetUrl // .name // .context // (.|@json))})' <<<"$checks")
diff=$(diff_by_key "$normalized_prev" "$normalized_curr" "id")
assert_equal "[]" "$diff" "Test 12: duplicate-named checks, unchanged"

# Test 13: an unchanged review request (keyed by login, no stable id) must not re-fire
rr='[{"login":"bob"}]'
normalized_prev=$(jq -c 'map(. + {id: (.login // .name)})' <<<"$rr")
normalized_curr=$(jq -c 'map(. + {id: (.login // .name)})' <<<"$rr")
diff=$(diff_by_key "$normalized_prev" "$normalized_curr" "id")
assert_equal "[]" "$diff" "Test 13: unchanged review request"

# Test 14: control characters (e.g. a forged terminal escape in a comment body) are
# stripped, not left to corrupt the watcher's own output
stripped=$(jq -rn --arg s $'line1\x1b[2Jline2\r' '$s | gsub("[[:cntrl:]]"; " ")')
assert_equal "line1 [2Jline2 " "$stripped" "Test 14: control-char stripping"

# Test 15: diff_removed_by_key reports an item present in prev but gone from curr
diff=$(diff_removed_by_key '[{"id":1,"body":"a"},{"id":2,"body":"b"}]' '[{"id":1,"body":"a"}]' "id")
ids=$(jq -c 'map(.id)' <<<"$diff")
assert_equal "[2]" "$ids" "Test 15: deletion detected"

# Test 16: diff_removed_by_key reports nothing when nothing was removed (only added)
diff=$(diff_removed_by_key '[{"id":1,"body":"a"}]' '[{"id":1,"body":"a"},{"id":2,"body":"b"}]' "id")
assert_equal "[]" "$diff" "Test 16: no false-positive deletion on pure addition"

# Test 17: diff_removed_by_key does not confuse an edit with a deletion
diff=$(diff_removed_by_key '[{"id":1,"body":"a"}]' '[{"id":1,"body":"EDITED"}]' "id")
assert_equal "[]" "$diff" "Test 17: edited item is not reported as deleted"

echo ""
echo "Tests passed: $tests_passed"
echo "Tests failed: $tests_failed"

if [[ $tests_failed -eq 0 ]]; then
  echo "all tests passed"
  exit 0
else
  echo "some tests failed" >&2
  exit 1
fi
