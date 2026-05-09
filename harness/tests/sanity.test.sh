#!/usr/bin/env bash
# Sanity tests — verify the test scaffold itself works.
# These should always pass on every commit.

test_assert_eq_pass() {
  assert_eq "hello" "hello" "literal string match"
}

test_assert_eq_fail_message() {
  # Run the failing assertion in a subshell so this test passes when
  # assert_eq correctly reports a mismatch.
  local out
  out=$(assert_eq "a" "b" 2>&1) && return 1
  assert_contains "$out" "expected" "failure message includes 'expected'"
  assert_contains "$out" "actual"   "failure message includes 'actual'"
}

test_assert_file_pass() {
  : > sentinel.txt
  assert_file sentinel.txt
}

test_assert_no_file_pass() {
  assert_no_file does-not-exist.txt
}

test_assert_exit_pass() {
  LABEL="exit 0" assert_exit 0 true
  LABEL="exit 1" assert_exit 1 false
}

test_isolate_tmp_unique() {
  local a b
  a=$(isolate_tmp)
  b=$(isolate_tmp)
  assert_neq "$a" "$b" "two tmp dirs differ"
  rm -rf "$a" "$b"
}

test_make_build_state_writes_valid_json() {
  local file
  file=$(make_build_state ".harness" "phase1")
  assert_file "$file"
  # Verify it parses as JSON.
  python3 -c "import json,sys; json.loads(open('$file').read())"
}

test_make_workflow_default() {
  local file
  file=$(make_workflow ".harness/workflow.yaml")
  assert_file "$file"
  local content
  content=$(cat "$file")
  assert_contains "$content" "name: test-workflow"
  assert_contains "$content" "phases:"
}
