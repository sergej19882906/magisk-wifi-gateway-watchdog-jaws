#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
POLICY="$ROOT/module/lib/watchdog-policy.sh"
FIXTURES="$ROOT/tests/fixtures"

. "$POLICY"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  [ "$1" = "$2" ] || fail "expected '$2', got '$1'"
}

assert_true() {
  "$@" || fail "expected success: $*"
}

assert_false() {
  if "$@"; then
    fail "expected failure: $*"
  fi
}

. "$FIXTURES/healthy.env"
assert_true policy_intent_allows_recovery "$WIFI_ON" "$AIRPLANE_MODE" "$FRAMEWORK_ENABLED"
assert_eq "$(policy_classify_gateway "$ROUTE_PRESENT" "$PING_OK" "$NEIGHBOR_STATE")" healthy
assert_false policy_should_recover 1 0 healthy 0 0 0

. "$FIXTURES/user-off.env"
assert_false policy_intent_allows_recovery "$WIFI_ON" "$AIRPLANE_MODE" "$FRAMEWORK_ENABLED"
assert_false policy_should_recover 0 0 disconnected 0 600 1

assert_false policy_intent_allows_recovery 3 1 0
assert_false policy_intent_allows_recovery 1 1 1
assert_true policy_intent_allows_recovery 2 1 1
assert_false policy_intent_allows_recovery 1 0 0

. "$FIXTURES/gateway-failed.env"
assert_eq "$(policy_classify_gateway "$ROUTE_PRESENT" "$PING_OK" "$NEIGHBOR_STATE")" bad
assert_false policy_should_recover 1 0 bad 1 0 0
assert_false policy_should_recover 1 0 bad 2 0 0
assert_true policy_should_recover 1 0 bad 3 0 0
assert_false policy_should_recover 1 1 bad 3 0 0
assert_false policy_should_recover 0 0 bad 3 0 0

assert_eq "$(policy_classify_gateway 1 1 FAILED)" healthy
assert_eq "$(policy_classify_gateway 1 0 REACHABLE)" healthy
assert_eq "$(policy_classify_gateway 1 0 STALE)" healthy
assert_eq "$(policy_classify_gateway 1 0 UNKNOWN)" neutral
assert_eq "$(policy_classify_gateway 0 0 UNKNOWN)" bad

assert_false policy_should_recover 1 0 disconnected 0 120 0
assert_false policy_should_recover 1 0 disconnected 0 119 1
assert_true policy_should_recover 1 0 disconnected 0 120 1

assert_eq "$(policy_rate_limit 1000 0 0 0 0)" allow
assert_eq "$(policy_rate_limit 10000 11000 0 0 0)" cooldown
assert_eq "$(policy_rate_limit 10000 0 11000 0 0)" lockout
assert_eq "$(policy_rate_limit 30000 0 0 29000 28000)" burst
assert_eq "$(policy_rate_limit 30000 0 0 29000 1000)" allow
assert_eq "$(policy_rate_limit 30000 0 0 0 0)" allow

echo "policy tests passed"
