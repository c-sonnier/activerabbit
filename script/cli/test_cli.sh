#!/bin/sh
# ActiveRabbit CLI — Test Suite
# Run: sh script/cli/test_cli.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLI="${SCRIPT_DIR}/activerabbit"
PASS=0
FAIL=0
TOTAL=0

# ─── Test Helpers ─────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

assert() {
  test_name="$1"
  TOTAL=$((TOTAL + 1))

  if eval "$2" >/dev/null 2>&1; then
    PASS=$((PASS + 1))
    printf "  ${GREEN}✓${RESET} %s\n" "$test_name"
  else
    FAIL=$((FAIL + 1))
    printf "  ${RED}✗${RESET} %s\n" "$test_name"
    if [ -n "${3:-}" ]; then
      printf "    ${DIM}%s${RESET}\n" "$3"
    fi
  fi
}

assert_contains() {
  test_name="$1"
  actual="$2"
  expected="$3"
  TOTAL=$((TOTAL + 1))

  if echo "$actual" | grep -q "$expected"; then
    PASS=$((PASS + 1))
    printf "  ${GREEN}✓${RESET} %s\n" "$test_name"
  else
    FAIL=$((FAIL + 1))
    printf "  ${RED}✗${RESET} %s — expected to contain: %s\n" "$test_name" "$expected"
    printf "    ${DIM}Got: %.100s${RESET}\n" "$actual"
  fi
}

assert_exit_code() {
  test_name="$1"
  expected_code="$2"
  shift 2
  TOTAL=$((TOTAL + 1))

  set +e
  output=$("$@" 2>&1)
  actual_code=$?
  set -e

  if [ "$actual_code" = "$expected_code" ]; then
    PASS=$((PASS + 1))
    printf "  ${GREEN}✓${RESET} %s\n" "$test_name"
  else
    FAIL=$((FAIL + 1))
    printf "  ${RED}✗${RESET} %s — expected exit %s, got %s\n" "$test_name" "$expected_code" "$actual_code"
  fi
}

# ─── Setup ────────────────────────────────────────────────────────────────────

# Use a temp config dir for tests
TEST_DIR=$(mktemp -d)
export XDG_CONFIG_HOME="${TEST_DIR}/.config"
export NO_COLOR=1

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

printf "\n${BOLD}ActiveRabbit CLI — Test Suite${RESET}\n\n"

# ─── Test: Script Basics ─────────────────────────────────────────────────────

printf "${CYAN}Script basics${RESET}\n"

assert "CLI script exists" "[ -f '$CLI' ]"
assert "CLI script is executable or can be run with sh" "sh '$CLI' version >/dev/null 2>&1"

version_output=$(sh "$CLI" version 2>&1)
assert_contains "Version command outputs version string" "$version_output" "activerabbit"

help_output=$(sh "$CLI" help 2>&1)
assert_contains "Help shows USAGE" "$help_output" "USAGE"
assert_contains "Help shows login command" "$help_output" "login"
assert_contains "Help shows status command" "$help_output" "status"
assert_contains "Help shows incidents command" "$help_output" "incidents"
assert_contains "Help shows explain command" "$help_output" "explain"
assert_contains "Help shows deploy-check command" "$help_output" "deploy-check"
assert_contains "Help shows doctor command" "$help_output" "doctor"
assert_contains "Help shows environment variables" "$help_output" "ACTIVERABBIT_API_KEY"

# --help and -h aliases
help_flag=$(sh "$CLI" --help 2>&1)
assert_contains "--help flag works" "$help_flag" "USAGE"

help_h=$(sh "$CLI" -h 2>&1)
assert_contains "-h flag works" "$help_h" "USAGE"

version_flag=$(sh "$CLI" --version 2>&1)
assert_contains "--version flag works" "$version_flag" "activerabbit"

version_v=$(sh "$CLI" -v 2>&1)
assert_contains "-v flag works" "$version_v" "activerabbit"

# ─── Test: Unknown Command ───────────────────────────────────────────────────

printf "\n${CYAN}Error handling${RESET}\n"

assert_exit_code "Unknown command exits with 1" 1 sh "$CLI" nonexistent

unknown_output=$(sh "$CLI" nonexistent 2>&1 || true)
assert_contains "Unknown command shows error" "$unknown_output" "Unknown command"

# ─── Test: Config Management ─────────────────────────────────────────────────

printf "\n${CYAN}Config management${RESET}\n"

# Config dir should not exist yet
assert "Config dir does not exist initially" "[ ! -d '${TEST_DIR}/.config/activerabbit' ]"

# use-app without arg should fail
assert_exit_code "use-app without arg exits with 1" 1 sh "$CLI" use-app

# use-app should create config
sh "$CLI" use-app test-app 2>/dev/null
assert "use-app creates config dir" "[ -d '${TEST_DIR}/.config/activerabbit' ]"
assert "use-app creates config file" "[ -f '${TEST_DIR}/.config/activerabbit/config' ]"

config_content=$(cat "${TEST_DIR}/.config/activerabbit/config")
assert_contains "Config contains app slug" "$config_content" "app=test-app"

# Check file permissions (should be 600)
if [ "$(uname -s)" != "MINGW"* ]; then
  perms=$(stat -f "%Lp" "${TEST_DIR}/.config/activerabbit/config" 2>/dev/null || stat -c "%a" "${TEST_DIR}/.config/activerabbit/config" 2>/dev/null || echo "unknown")
  if [ "$perms" != "unknown" ]; then
    assert "Config file has 600 permissions" "[ '$perms' = '600' ]" "Got: $perms"
  fi
fi

# Update existing key
sh "$CLI" use-app updated-app 2>/dev/null
config_content=$(cat "${TEST_DIR}/.config/activerabbit/config")
assert_contains "use-app updates existing config" "$config_content" "app=updated-app"

# Config should not have duplicate entries
dup_count=$(grep -c "^app=" "${TEST_DIR}/.config/activerabbit/config")
assert "No duplicate config entries" "[ '$dup_count' = '1' ]" "Found $dup_count entries"

# ─── Test: Require API Key ───────────────────────────────────────────────────

printf "\n${CYAN}Authentication checks${RESET}\n"

# Commands that require API key should fail gracefully
assert_exit_code "status without API key exits with 1" 1 sh "$CLI" status

status_no_key=$(sh "$CLI" status 2>&1 || true)
assert_contains "status without API key shows login hint" "$status_no_key" "login"

assert_exit_code "incidents without API key exits with 1" 1 sh "$CLI" incidents
assert_exit_code "apps without API key exits with 1" 1 sh "$CLI" apps

# ─── Test: Require App ───────────────────────────────────────────────────────

printf "\n${CYAN}App selection checks${RESET}\n"

# Set API key but remove app
export ACTIVERABBIT_API_KEY="test_key_12345"
rm -f "${TEST_DIR}/.config/activerabbit/config"

# Set a dummy base URL that won't connect (to test app requirement before HTTP)
export ACTIVERABBIT_BASE_URL="http://127.0.0.1:1"

# apps command should attempt API call (doesn't require app), so it will fail on connection
# but status requires app first
unset ACTIVERABBIT_APP 2>/dev/null || true

status_no_app=$(sh "$CLI" status 2>&1 || true)
assert_contains "status without app shows use-app hint" "$status_no_app" "use-app"

# ─── Test: Doctor Command (offline) ──────────────────────────────────────────

printf "\n${CYAN}Doctor command${RESET}\n"

unset ACTIVERABBIT_API_KEY 2>/dev/null || true
unset ACTIVERABBIT_BASE_URL 2>/dev/null || true

# Doctor should work even without config
doctor_output=$(sh "$CLI" doctor 2>&1 || true)
assert_contains "Doctor checks config file" "$doctor_output" "Config file"
assert_contains "Doctor checks API key" "$doctor_output" "API key"
assert_contains "Doctor checks jq" "$doctor_output" "jq"
assert_contains "Doctor checks HTTP client" "$doctor_output" "HTTP client"

# With API key set
export ACTIVERABBIT_API_KEY="test_masked_key"
doctor_output2=$(sh "$CLI" doctor 2>&1 || true)
assert_contains "Doctor masks API key" "$doctor_output2" "test..._key"

unset ACTIVERABBIT_API_KEY 2>/dev/null || true

# ─── Test: Environment Variable Override ──────────────────────────────────────

printf "\n${CYAN}Environment variable overrides${RESET}\n"

# Set app via env var
export ACTIVERABBIT_APP="env-app"
export ACTIVERABBIT_API_KEY="env_key"
export ACTIVERABBIT_BASE_URL="http://127.0.0.1:1"

# Status should use env app (will fail on connection, but should get past the app check)
status_env=$(sh "$CLI" status 2>&1 || true)
# Should NOT say "No app selected" since we set it via env
assert "Env var ACTIVERABBIT_APP overrides config" "! echo '$status_env' | grep -q 'No app selected'"

unset ACTIVERABBIT_APP ACTIVERABBIT_API_KEY ACTIVERABBIT_BASE_URL 2>/dev/null || true

# ─── Test: Installer Script ──────────────────────────────────────────────────

printf "\n${CYAN}Installer script${RESET}\n"

INSTALLER="${SCRIPT_DIR}/install.sh"
assert "Installer script exists" "[ -f '$INSTALLER' ]"

# Check installer has proper shebang
first_line=$(head -1 "$INSTALLER")
assert_contains "Installer has sh shebang" "$first_line" "#!/bin/sh"

# Check installer contains key functions
installer_content=$(cat "$INSTALLER")
assert_contains "Installer has platform detection" "$installer_content" "detect_platform"
assert_contains "Installer has jq install" "$installer_content" "install_jq"
assert_contains "Installer has download function" "$installer_content" "download"
assert_contains "Installer checks for curl/wget" "$installer_content" "check_http_client"
assert_contains "Installer handles Windows" "$installer_content" "MINGW"
assert_contains "Installer handles WSL" "$installer_content" "microsoft"
assert_contains "Installer references activerabbit.ai" "$installer_content" "activerabbit.ai"

# ─── Test: Shell Compatibility ────────────────────────────────────────────────

printf "\n${CYAN}Shell compatibility${RESET}\n"

# Check no bash-specific syntax (common issues)
cli_content=$(cat "$CLI")

# Check for bashisms
if command -v checkbashisms >/dev/null 2>&1; then
  if checkbashisms "$CLI" 2>&1; then
    TOTAL=$((TOTAL + 1))
    PASS=$((PASS + 1))
    printf "  ${GREEN}✓${RESET} No bashisms detected (checkbashisms)\n"
  else
    TOTAL=$((TOTAL + 1))
    FAIL=$((FAIL + 1))
    printf "  ${RED}✗${RESET} Bashisms detected\n"
  fi
else
  # Manual checks for common bashisms
  assert "No [[ syntax" "! grep -n '\[\[' '$CLI'"
  assert "No standalone (( syntax (POSIX \$(( )) is ok)" "! grep -n '^[^$]*((' '$CLI' | grep -v '\$(('"
  assert "No function keyword" "! grep -n '^function ' '$CLI'"
  assert "No &> redirect" "! grep -n '&>' '$CLI'"
  assert "No <<<  herestring" "! grep -n '<<<' '$CLI'"
fi

# Verify shebang
cli_first_line=$(head -1 "$CLI")
assert_contains "CLI has sh shebang" "$cli_first_line" "#!/bin/sh"

# ─── Summary ─────────────────────────────────────────────────────────────────

printf "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
printf "${BOLD}Results:${RESET} %s passed, %s failed, %s total\n" "$PASS" "$FAIL" "$TOTAL"
printf "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n\n"

if [ "$FAIL" -gt 0 ]; then
  printf "${RED}${BOLD}FAILED${RESET}\n\n"
  exit 1
else
  printf "${GREEN}${BOLD}ALL TESTS PASSED${RESET}\n\n"
  exit 0
fi
