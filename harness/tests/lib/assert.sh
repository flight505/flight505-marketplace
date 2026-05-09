#!/usr/bin/env bash
# Minimal assertion helpers for harness shell tests. Sourced by test files.
# Each assertion failure prints a labeled message to stderr and returns 1, which
# the test runner uses to mark the enclosing test as failed.

assert_eq() {
  local actual="$1"
  local expected="$2"
  local label="${3:-assert_eq}"
  if [ "$actual" != "$expected" ]; then
    printf '  FAIL [%s]\n    expected: %q\n    actual:   %q\n' \
      "$label" "$expected" "$actual" >&2
    return 1
  fi
}

assert_neq() {
  local actual="$1"
  local unexpected="$2"
  local label="${3:-assert_neq}"
  if [ "$actual" = "$unexpected" ]; then
    printf '  FAIL [%s]\n    value should not equal: %q\n' \
      "$label" "$unexpected" >&2
    return 1
  fi
}

assert_empty() {
  local actual="$1"
  local label="${2:-assert_empty}"
  if [ -n "$actual" ]; then
    printf '  FAIL [%s]\n    expected empty, got: %q\n' "$label" "$actual" >&2
    return 1
  fi
}

assert_nonempty() {
  local actual="$1"
  local label="${2:-assert_nonempty}"
  if [ -z "$actual" ]; then
    printf '  FAIL [%s]\n    expected non-empty\n' "$label" >&2
    return 1
  fi
}

assert_file() {
  local path="$1"
  local label="${2:-assert_file}"
  if [ ! -f "$path" ]; then
    printf '  FAIL [%s]\n    expected file at: %s\n' "$label" "$path" >&2
    return 1
  fi
}

assert_no_file() {
  local path="$1"
  local label="${2:-assert_no_file}"
  if [ -e "$path" ]; then
    printf '  FAIL [%s]\n    expected no file at: %s\n' "$label" "$path" >&2
    return 1
  fi
}

assert_exit() {
  local expected="$1"
  shift
  local label="${LABEL:-assert_exit}"
  local rc=0
  "$@" >/dev/null 2>&1 || rc=$?
  if [ "$rc" != "$expected" ]; then
    printf '  FAIL [%s]\n    expected exit %d, got %d\n    cmd: %s\n' \
      "$label" "$expected" "$rc" "$*" >&2
    return 1
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="${3:-assert_contains}"
  case "$haystack" in
    *"$needle"*) return 0 ;;
    *)
      printf '  FAIL [%s]\n    expected to contain: %q\n    in: %q\n' \
        "$label" "$needle" "$haystack" >&2
      return 1
      ;;
  esac
}
