#!/usr/bin/env bash
# Harness test runner.
#
# Discovers and executes:
#   - *.test.sh files (bash; each defines test_* functions)
#   - *.test.mjs files (delegated to `node --test`)
#
# Each bash test runs in its own subshell with a fresh tmpdir as PWD, so tests
# cannot leak state between each other. Failure is signaled by a non-zero
# return from any assert_* helper.
#
# Usage:
#   harness/tests/run.sh                  # run all tests
#   harness/tests/run.sh path/to/file     # run a single test file
#
# Environment:
#   HARNESS_TEST_VERBOSE=1   # show stdout/stderr of passing tests
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TESTS_DIR="$REPO_ROOT/harness/tests"
export HARNESS_TESTS_LIB="$TESTS_DIR/lib"
export HARNESS_REPO_ROOT="$REPO_ROOT"

PASS=0
FAIL=0
FAIL_LIST=()

red()   { printf '\033[31m%s\033[0m' "$1"; }
green() { printf '\033[32m%s\033[0m' "$1"; }
dim()   { printf '\033[2m%s\033[0m' "$1"; }

# Run one bash test file. Sources the file in a subshell, finds test_* funcs,
# and runs each in its own subshell with a fresh tmpdir.
run_bash_file() {
  local file="$1"
  local rel="${file#"$REPO_ROOT"/}"
  printf '%s\n' "$(dim "▸ $rel")"

  local tests=()
  # Extract test_* function names by sourcing in a subshell.
  while IFS= read -r name; do
    tests+=("$name")
  done < <(
    bash -c "
      set +e
      source '$HARNESS_TESTS_LIB/assert.sh'
      source '$HARNESS_TESTS_LIB/fixtures.sh'
      source '$file'
      declare -F | awk '\$3 ~ /^test_/ {print \$3}'
    "
  )

  if [ "${#tests[@]}" -eq 0 ]; then
    printf '  %s no test_* functions found\n' "$(red "FAIL")"
    FAIL=$((FAIL + 1))
    FAIL_LIST+=("$rel: no tests")
    return
  fi

  for tname in "${tests[@]}"; do
    local tmp
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/harness-test.XXXXXX")
    local out
    out=$(
      cd "$tmp" && bash -c "
        set -uo pipefail
        source '$HARNESS_TESTS_LIB/assert.sh'
        source '$HARNESS_TESTS_LIB/fixtures.sh'
        source '$file'
        $tname
      " 2>&1
    )
    local rc=$?
    rm -rf "$tmp"
    if [ "$rc" -eq 0 ]; then
      printf '  %s %s\n' "$(green '✓')" "$tname"
      [ "${HARNESS_TEST_VERBOSE:-0}" = "1" ] && [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/    /'
      PASS=$((PASS + 1))
    else
      printf '  %s %s\n' "$(red '✗')" "$tname"
      [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/    /'
      FAIL=$((FAIL + 1))
      FAIL_LIST+=("$rel::$tname")
    fi
  done
}

# Run a node test file via `node --test`.
run_node_file() {
  local file="$1"
  local rel="${file#"$REPO_ROOT"/}"
  printf '%s\n' "$(dim "▸ $rel")"
  local out
  out=$(node --test "$file" 2>&1)
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '  %s ok\n' "$(green '✓')"
    [ "${HARNESS_TEST_VERBOSE:-0}" = "1" ] && printf '%s\n' "$out" | sed 's/^/    /'
    PASS=$((PASS + 1))
  else
    printf '  %s failed\n' "$(red '✗')"
    printf '%s\n' "$out" | sed 's/^/    /'
    FAIL=$((FAIL + 1))
    FAIL_LIST+=("$rel")
  fi
}

# Determine which files to run.
FILES=()
if [ "$#" -gt 0 ]; then
  FILES=("$@")
else
  while IFS= read -r f; do FILES+=("$f"); done < <(
    find "$TESTS_DIR" -type f \( -name '*.test.sh' -o -name '*.test.mjs' \) | sort
  )
fi

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "No test files found under $TESTS_DIR"
  exit 0
fi

for file in "${FILES[@]}"; do
  case "$file" in
    *.test.sh)  run_bash_file "$file" ;;
    *.test.mjs) run_node_file "$file" ;;
    *) printf '  %s unknown test file type: %s\n' "$(red 'SKIP')" "$file" ;;
  esac
done

printf '\n%s %d passed, %d failed\n' "$(dim '──')" "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf '\nFailures:\n'
  for f in "${FAIL_LIST[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi
