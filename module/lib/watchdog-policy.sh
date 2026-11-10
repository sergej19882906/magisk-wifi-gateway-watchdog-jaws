#!/system/bin/sh

policy_intent_allows_recovery() {
  wifi_on=$1
  airplane_mode=$2
  framework_enabled=$3

  case "$wifi_on:$airplane_mode" in
    1:0|2:0|2:1) ;;
    *) return 1 ;;
  esac

  [ "$framework_enabled" = 1 ] || return 1
}

policy_classify_gateway() {
  route_present=$1
  ping_ok=$2
  neighbor_state=$3

  if [ "$ping_ok" = 1 ]; then
    echo healthy
    return
  fi

  if [ "$route_present" != 1 ]; then
    echo bad
    return
  fi

  case "$neighbor_state" in
    FAILED|INCOMPLETE)
      echo bad
      ;;
    REACHABLE|STALE|DELAY|PROBE|PERMANENT)
      echo healthy
      ;;
    *)
      echo neutral
      ;;
  esac
}

policy_should_recover() {
  has_healthy=$1
  grace_active=$2
  classification=$3
  bad_streak=$4
  disconnected_seconds=$5
  reachability_latched=$6

  [ "$has_healthy" = 1 ] || return 1
  [ "$grace_active" = 0 ] || return 1

  if [ "$classification" = bad ] && [ "$bad_streak" -ge 3 ]; then
    return 0
  fi

  if [ "$classification" = disconnected ] \
      && [ "$reachability_latched" = 1 ] \
      && [ "$disconnected_seconds" -ge 120 ]; then
    return 0
  fi

  return 1
}

policy_rate_limit() {
  now=$1
  cooldown_until=$2
  lockout_until=$3
  recovery_one=$4
  recovery_two=$5

  if [ "$now" -lt "$lockout_until" ]; then
    echo lockout
    return
  fi

  if [ "$now" -lt "$cooldown_until" ]; then
    echo cooldown
    return
  fi

  cutoff=$((now - 21600))
  count=0
  [ "$recovery_one" -gt 0 ] && [ "$recovery_one" -gt "$cutoff" ] && count=$((count + 1))
  [ "$recovery_two" -gt 0 ] && [ "$recovery_two" -gt "$cutoff" ] && count=$((count + 1))

  if [ "$count" -ge 2 ]; then
    echo burst
  else
    echo allow
  fi
}
