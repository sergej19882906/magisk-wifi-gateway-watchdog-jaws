#!/system/bin/sh

MODDIR=${0%/*}
POLICY="$MODDIR/lib/watchdog-policy.sh"
LOG_FILE="$MODDIR/service.log"
LOG_BACKUP="$MODDIR/service.log.1"
PID_FILE="$MODDIR/service.pid"
LOCK_DIR="$MODDIR/service.lock"
STATE_DIR="$MODDIR/state"
SNAPSHOT_DIR="$MODDIR/snapshots"
OBSERVE_ONLY="$MODDIR/observe_only"

GETPROP=/system/bin/getprop
SETTINGS=/system/bin/settings
CMD=/system/bin/cmd
IP=/system/bin/ip
IW=/system/bin/iw
PING=/system/bin/ping
TIMEOUT=/system/bin/timeout
SLEEP=/system/bin/sleep
CAT=/system/bin/cat
STAT=/system/bin/stat
TAIL=/system/bin/tail
HEAD=/system/bin/head
GREP=/system/bin/grep
AWK=/system/bin/awk
CUT=/system/bin/cut
DATE=/system/bin/date
DUMPSYS=/system/bin/dumpsys
LOGCAT=/system/bin/logcat
DMESG=/system/bin/dmesg
MV=/system/bin/mv
RM=/system/bin/rm
CHMOD=/system/bin/chmod
MKDIR=/system/bin/mkdir
RMDIR=/system/bin/rmdir
TR=/system/bin/tr
ID=/system/bin/id

CHECK_INTERVAL=15
BOOT_DELAY=60
GRACE_SECONDS=120
COOLDOWN_SECONDS=1800
LOCKOUT_SECONDS=21600
RECOVERY_TIMEOUT=120
MAX_LOG_SIZE=65536
MAX_SNAPSHOT_SIZE=262144

. "$POLICY"

cleanup() {
  owner=$($CAT "$LOCK_DIR/pid" 2>/dev/null)
  if [ "$owner" = "$$" ]; then
    pid_owner=$($CAT "$PID_FILE" 2>/dev/null)
    [ "$pid_owner" = "$$" ] && $RM -f "$PID_FILE"
    $RM -f "$LOCK_DIR/pid"
    $RMDIR "$LOCK_DIR" 2>/dev/null || true
  fi
}

stop_service() {
  cleanup
  exit 0
}

interruptible_sleep() {
  remaining=$1
  while [ "$remaining" -gt 0 ]; do
    if [ -f "$MODDIR/disable" ] || [ -f "$MODDIR/remove" ]; then
      return 1
    fi
    $SLEEP 1
    remaining=$((remaining - 1))
  done
}

uptime_seconds() {
  value=$($CAT /proc/uptime 2>/dev/null)
  value=${value%%.*}
  case "$value" in
    ''|*[!0-9]*) echo 0 ;;
    *) echo "$value" ;;
  esac
}

read_number() {
  value=$($CAT "$1" 2>/dev/null)
  case "$value" in
    ''|*[!0-9]*) echo "$2" ;;
    *) echo "$value" ;;
  esac
}

write_value() {
  temporary="$1.tmp.$$"
  printf '%s\n' "$2" > "$temporary" || return 1
  $CHMOD 0600 "$temporary" || {
    $RM -f "$temporary"
    return 1
  }
  $MV -f "$temporary" "$1" || {
    $RM -f "$temporary"
    return 1
  }
}

rotate_log() {
  size=$($STAT -c %s "$LOG_FILE" 2>/dev/null)
  case "$size" in
    ''|*[!0-9]*) size=0 ;;
  esac
  if [ "$size" -ge "$MAX_LOG_SIZE" ]; then
    $MV -f "$LOG_FILE" "$LOG_BACKUP"
  fi
}

log() {
  rotate_log
  printf '%s: %s\n' "$($DATE '+%Y-%m-%d %H:%M:%S%z')" "$*" >> "$LOG_FILE"
}

acquire_lock() {
  if $MKDIR "$LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" > "$LOCK_DIR/pid" || return 1
    $CHMOD 0700 "$LOCK_DIR"
    $CHMOD 0600 "$LOCK_DIR/pid"
    return 0
  fi

  owner=$($CAT "$LOCK_DIR/pid" 2>/dev/null)
  case "$owner" in
    ''|*[!0-9]*) ;;
    *)
      cmdline=$($TR '\000' ' ' < "/proc/$owner/cmdline" 2>/dev/null)
      case "$cmdline" in
        *"$MODDIR/service.sh"*) return 1 ;;
      esac
      ;;
  esac

  $RM -rf "$LOCK_DIR"
  $MKDIR "$LOCK_DIR" 2>/dev/null || return 1
  printf '%s\n' "$$" > "$LOCK_DIR/pid" || return 1
  $CHMOD 0700 "$LOCK_DIR"
  $CHMOD 0600 "$LOCK_DIR/pid"
}

get_interface() {
  interface=$($GETPROP wifi.active.interface)
  [ -n "$interface" ] || interface=$($GETPROP wifi.interface)
  [ -n "$interface" ] || interface=wlan0
  echo "$interface"
}

wifi_setting() {
  $TIMEOUT 5 "$SETTINGS" get global "$1" 2>/dev/null
}

framework_status() {
  $TIMEOUT 10 "$CMD" wifi status 2>/dev/null
}

framework_enabled() {
  printf '%s\n' "$1" | $GREP -q '^Wifi is enabled$'
}

framework_connected() {
  printf '%s\n' "$1" | $GREP -q '^Wifi is connected to '
}

current_ipv4() {
  $TIMEOUT 5 "$IP" -4 -o addr show dev "$1" 2>/dev/null \
    | "$AWK" 'NR==1 {print $4}' \
    | "$CUT" -d/ -f1
}

current_bssid() {
  $TIMEOUT 5 "$IW" dev "$1" link 2>/dev/null \
    | "$AWK" '/^Connected to / {print $3; exit}'
}

parse_default_gateway() {
  "$AWK" -v target="$1" '
    $1 == "default" {
      gateway=""; device=""
      for (i=1; i<=NF; i++) {
        if ($i == "via" && i < NF) gateway=$(i+1)
        if ($i == "dev" && i < NF) device=$(i+1)
      }
      if (device == target && gateway != "") {
        print gateway
        exit
      }
    }
  '
}

current_gateway() {
  gateway=$($TIMEOUT 5 "$IP" -4 route show table "$1" 2>/dev/null \
    | parse_default_gateway "$1")
  if [ -z "$gateway" ]; then
    gateway=$($TIMEOUT 5 "$IP" -4 route show table all 2>/dev/null \
      | parse_default_gateway "$1")
  fi
  echo "$gateway"
}

neighbor_state() {
  $TIMEOUT 5 "$IP" -4 neigh show to "$2" dev "$1" 2>/dev/null \
    | "$AWK" 'NR==1 {print $NF}'
}

gateway_probe() {
  "$TIMEOUT" 6 "$PING" -q -c 1 -W 2 -w 4 -I "$1" "$2" >/dev/null 2>&1
}

latest_reachability_event() {
  $TIMEOUT 10 "$DUMPSYS" wifi 2>/dev/null \
    | $GREP 'CMD_IP_REACHABILITY_FAILURE' \
    | $TAIL -n 1
}

cap_snapshot() {
  snapshot=$1
  size=$($STAT -c %s "$snapshot" 2>/dev/null)
  case "$size" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$size" -le "$MAX_SNAPSHOT_SIZE" ] && return 0

  header="$snapshot.header.$$"
  body="$snapshot.body.$$"
  capped="$snapshot.capped.$$"
  body_size=$((MAX_SNAPSHOT_SIZE - 4160))
  $HEAD -c 4096 "$snapshot" > "$header" || return 1
  $TAIL -c "$body_size" "$snapshot" > "$body" || return 1
  {
    $CAT "$header"
    echo
    echo '[... middle truncated ...]'
    $CAT "$body"
  } > "$capped" || return 1
  $MV -f "$capped" "$snapshot" || return 1
  $RM -f "$header" "$body"
  $CHMOD 0600 "$snapshot"
}

capture_snapshot() {
  reason=$1
  phase=$2
  now=$3
  slot=$(read_number "$STATE_DIR/snapshot_slot" 0)
  slot=$((slot % 3))
  snapshot="$SNAPSHOT_DIR/snapshot-$slot.txt"
  temporary="$snapshot.tmp.$$"
  interface=$(get_interface)
  gateway=$(current_gateway "$interface")

  {
    echo "phase=$phase"
    echo "reason=$reason"
    echo "uptime=$now"
    echo "boot_id=$($CAT /proc/sys/kernel/random/boot_id 2>/dev/null)"
    echo "date=$($DATE '+%Y-%m-%d %H:%M:%S%z')"
    echo "device=$($GETPROP ro.product.device)"
    echo "soc=$($GETPROP ro.soc.model)"
    echo "sdk=$($GETPROP ro.build.version.sdk)"
    echo "wifi_on=$(wifi_setting wifi_on)"
    echo "airplane_mode=$(wifi_setting airplane_mode_on)"
    echo "interface=$interface"
    echo "gateway=$gateway"
    echo
    echo '[cmd wifi status]'
    framework_status | $TAIL -n 35
    echo
    echo '[ip addr]'
    $TIMEOUT 5 "$IP" -brief addr show "$interface" 2>/dev/null
    echo
    echo '[ip rule]'
    $TIMEOUT 5 "$IP" -4 rule show 2>/dev/null | $TAIL -n 40
    echo
    echo '[ip route table]'
    $TIMEOUT 5 "$IP" -4 route show table "$interface" 2>/dev/null | $TAIL -n 40
    echo
    echo '[ip neigh]'
    $TIMEOUT 5 "$IP" -4 neigh show dev "$interface" 2>/dev/null | $TAIL -n 80
    echo
    echo '[iw link]'
    $TIMEOUT 5 "$IW" dev "$interface" link 2>/dev/null | $TAIL -n 30
    echo
    echo '[iw power save]'
    $TIMEOUT 5 "$IW" dev "$interface" get power_save 2>/dev/null
    echo
    echo '[wifi framework tail]'
    $TIMEOUT 10 "$DUMPSYS" wifi 2>/dev/null \
      | $GREP -iE 'WifiState|Current wifi mode|CMD_IP_REACHABILITY_FAILURE|LOST_PROVISIONING|NUD_FAILED|CMD_IP_CONFIGURATION_LOST|NETWORK_SELECTION_DISABLED_NO_INTERNET|Blocklist' \
      | $TAIL -n 120
    echo
    echo '[connectivity current network]'
    $TIMEOUT 10 "$DUMPSYS" connectivity 2>/dev/null \
      | $GREP -iE 'Active default network|NetworkAgentInfo\{network|InterfaceName:|0\.0\.0\.0/0|VALIDATED|NOT_SUSPENDED' \
      | $TAIL -n 80
    echo
    echo '[logcat wifi tail]'
    $TIMEOUT 10 "$LOGCAT" -b all -d -v brief -t 300 2>/dev/null \
      | $GREP -iE 'Wifi|wlan0|IpClient|DhcpClient|ConnectivityService|NUD_FAILED|LOST_PROVISIONING' \
      | $TAIL -n 150
    echo
    echo '[kernel wifi tail]'
    $TIMEOUT 10 "$DMESG" 2>/dev/null \
      | $GREP -iE 'wlan|wifi|mt7663|usb 1-1|NUD_FAILED' \
      | $TAIL -n 100
  } > "$temporary" || {
    $RM -f "$temporary"
    return 1
  }

  $MV -f "$temporary" "$snapshot" || return 1
  $CHMOD 0600 "$snapshot" || return 1
  cap_snapshot "$snapshot" || return 1
  write_value "$STATE_DIR/snapshot_slot" $((slot + 1)) || return 1
  ACTIVE_SNAPSHOT="$snapshot"
}

append_snapshot_result() {
  [ -n "$ACTIVE_SNAPSHOT" ] || return 0
  {
    echo
    echo '[recovery result]'
    echo "result=$1"
    echo "uptime=$(uptime_seconds)"
    echo "wifi_on=$(wifi_setting wifi_on)"
    framework_status | $TAIL -n 20
  } >> "$ACTIVE_SNAPSHOT" || return 1
  cap_snapshot "$ACTIVE_SNAPSHOT"
}

sample_health() {
  SAMPLE_STATUS=$(framework_status)
  SAMPLE_FRAMEWORK_ENABLED=0
  SAMPLE_CONNECTED=0
  framework_enabled "$SAMPLE_STATUS" && SAMPLE_FRAMEWORK_ENABLED=1
  framework_connected "$SAMPLE_STATUS" && SAMPLE_CONNECTED=1
  SAMPLE_INTERFACE=$(get_interface)
  SAMPLE_IPV4=$(current_ipv4 "$SAMPLE_INTERFACE")
  SAMPLE_BSSID=$(current_bssid "$SAMPLE_INTERFACE")
  SAMPLE_GATEWAY=$(current_gateway "$SAMPLE_INTERFACE")
  SAMPLE_NEIGHBOR=
  SAMPLE_PING_OK=0
  SAMPLE_ROUTE_PRESENT=0

  if [ -n "$SAMPLE_GATEWAY" ]; then
    SAMPLE_ROUTE_PRESENT=1
    if gateway_probe "$SAMPLE_INTERFACE" "$SAMPLE_GATEWAY"; then
      SAMPLE_PING_OK=1
    fi
    SAMPLE_NEIGHBOR=$(neighbor_state "$SAMPLE_INTERFACE" "$SAMPLE_GATEWAY")
  fi

  if [ "$SAMPLE_CONNECTED" = 1 ] && [ -n "$SAMPLE_IPV4" ] && [ -n "$SAMPLE_GATEWAY" ]; then
    SAMPLE_CLASSIFICATION=$(policy_classify_gateway "$SAMPLE_ROUTE_PRESENT" "$SAMPLE_PING_OK" "$SAMPLE_NEIGHBOR")
  elif [ "$SAMPLE_FRAMEWORK_ENABLED" = 1 ]; then
    SAMPLE_CLASSIFICATION=disconnected
  else
    SAMPLE_CLASSIFICATION=neutral
  fi

  SAMPLE_SIGNATURE="$SAMPLE_INTERFACE|$SAMPLE_BSSID|$SAMPLE_IPV4|$SAMPLE_GATEWAY"
}

recovery_allowed() {
  now=$1
  cooldown_until=$(read_number "$STATE_DIR/cooldown_until" 0)
  lockout_until=$(read_number "$STATE_DIR/lockout_until" 0)
  recovery_one=$(read_number "$STATE_DIR/recovery_one" 0)
  recovery_two=$(read_number "$STATE_DIR/recovery_two" 0)
  POLICY_LIMIT=$(policy_rate_limit "$now" "$cooldown_until" "$lockout_until" "$recovery_one" "$recovery_two")
  [ "$POLICY_LIMIT" = allow ]
}

record_recovery() {
  now=$1
  previous=$(read_number "$STATE_DIR/recovery_one" 0)
  write_value "$STATE_DIR/recovery_two" "$previous" || return 1
  write_value "$STATE_DIR/recovery_one" "$now" || return 1
  write_value "$STATE_DIR/cooldown_until" $((now + COOLDOWN_SECONDS)) || return 1
}

recovery_fault_still_present() {
  reason=$1
  expected_bssid=$2
  expected_event=$3

  [ ! -f "$MODDIR/disable" ] || return 1
  [ ! -f "$MODDIR/remove" ] || return 1

  wifi_on=$(wifi_setting wifi_on)
  airplane=$(wifi_setting airplane_mode_on)
  sample_health
  policy_intent_allows_recovery "$wifi_on" "$airplane" "$SAMPLE_FRAMEWORK_ENABLED" || return 1

  case "$reason" in
    bad)
      if [ -n "$expected_bssid" ]; then
        [ -n "$SAMPLE_BSSID" ] || return 1
        [ "$SAMPLE_BSSID" = "$expected_bssid" ] || return 1
      fi
      [ "$SAMPLE_CLASSIFICATION" = bad ]
      ;;
    disconnected)
      [ "$SAMPLE_CLASSIFICATION" = disconnected ] || return 1
      current_event=$(latest_reachability_event)
      [ -n "$expected_event" ] && [ "$current_event" = "$expected_event" ]
      ;;
    *)
      return 1
      ;;
  esac
}

perform_recovery() {
  reason=$1
  expected_bssid=$2
  expected_event=$3
  now=$(uptime_seconds)
  wifi_on=$(wifi_setting wifi_on)
  airplane=$(wifi_setting airplane_mode_on)
  status=$(framework_status)
  enabled=0
  framework_enabled "$status" && enabled=1

  if ! policy_intent_allows_recovery "$wifi_on" "$airplane" "$enabled"; then
    log "recovery cancelled: user intent or framework state changed"
    return 1
  fi

  if ! recovery_allowed "$now"; then
    if [ "$POLICY_LIMIT" = burst ]; then
      write_value "$STATE_DIR/lockout_until" $((now + LOCKOUT_SECONDS)) || true
    fi
    log "recovery suppressed: $POLICY_LIMIT"
    return 1
  fi

  if ! capture_snapshot "$reason" pre "$now"; then
    log "recovery cancelled: unable to save diagnostic snapshot"
    return 1
  fi

  if ! recovery_fault_still_present "$reason" "$expected_bssid" "$expected_event"; then
    append_snapshot_result fault_cleared || true
    log "recovery cancelled: fault or user state changed during snapshot"
    return 1
  fi

  if [ -f "$OBSERVE_ONLY" ]; then
    write_value "$STATE_DIR/cooldown_until" $((now + COOLDOWN_SECONDS)) || true
    append_snapshot_result observe_only || true
    log "observe_only: detected $reason; no recovery executed"
    return 1
  fi

  if ! record_recovery "$now"; then
    append_snapshot_result state_write_failed || true
    log "recovery cancelled: unable to reserve rate-limit state"
    return 1
  fi

  log "triggering Wi-Fi subsystem recovery: $reason"
  if ! "$TIMEOUT" 15 "$CMD" wifi trigger-recovery >/dev/null 2>&1; then
    write_value "$STATE_DIR/lockout_until" $((now + LOCKOUT_SECONDS)) || true
    append_snapshot_result command_failed || true
    log "recovery command failed; lockout enabled"
    return 1
  fi

  deadline=$((now + RECOVERY_TIMEOUT))
  success_streak=0
  while [ "$(uptime_seconds)" -lt "$deadline" ]; do
    if [ -f "$MODDIR/disable" ] || [ -f "$MODDIR/remove" ]; then
      append_snapshot_result cancelled || true
      log "recovery wait cancelled: module disabled or removed"
      return 1
    fi

    interruptible_sleep 5 || {
      append_snapshot_result cancelled || true
      log "recovery wait cancelled"
      return 1
    }

    wifi_on=$(wifi_setting wifi_on)
    case "$wifi_on" in
      1|2) ;;
      *)
        append_snapshot_result user_disabled || true
        log "recovery wait stopped: Wi-Fi user intent changed"
        return 1
        ;;
    esac

    sample_health
    if [ "$SAMPLE_FRAMEWORK_ENABLED" = 1 ] \
        && [ "$SAMPLE_CONNECTED" = 1 ] \
        && [ -n "$SAMPLE_IPV4" ] \
        && [ -n "$SAMPLE_GATEWAY" ] \
        && [ "$SAMPLE_PING_OK" = 1 ]; then
      success_streak=$((success_streak + 1))
    else
      success_streak=0
    fi

    if [ "$success_streak" -ge 2 ]; then
      append_snapshot_result success || true
      log "Wi-Fi subsystem recovery succeeded"
      return 0
    fi
  done

  now=$(uptime_seconds)
  write_value "$STATE_DIR/lockout_until" $((now + LOCKOUT_SECONDS)) || true
  append_snapshot_result timeout || true
  log "recovery timed out; six-hour lockout enabled"
  return 1
}

umask 077
$MKDIR -p "$STATE_DIR" "$SNAPSHOT_DIR" || exit 1
if ! acquire_lock; then
  exit 0
fi
trap cleanup EXIT
trap stop_service INT TERM HUP
printf '%s\n' "$$" > "$PID_FILE" || exit 1
$CHMOD 0600 "$PID_FILE" || exit 1
write_value "$STATE_DIR/write_test" 1 || exit 1
$RM -f "$STATE_DIR/write_test"
rotate_log
log "start; context=$($ID)"

boot_id=$($CAT /proc/sys/kernel/random/boot_id 2>/dev/null)
stored_boot_id=$($CAT "$STATE_DIR/boot_id" 2>/dev/null)
if [ "$boot_id" != "$stored_boot_id" ]; then
  $RM -f "$STATE_DIR"/*
  write_value "$STATE_DIR/boot_id" "$boot_id" || exit 1
fi

while [ "$($GETPROP sys.boot_completed)" != 1 ]; do
  interruptible_sleep 2 || exit 0
done
interruptible_sleep "$BOOT_DELAY" || exit 0

has_healthy=0
healthy_bssid=
bad_streak=0
disconnected_since=0
reachability_latched=0
last_wifi_on=
last_signature=
grace_until=$(( $(uptime_seconds) + GRACE_SECONDS ))
last_logged_state=
last_classification=
next_event_check=0
last_reachability_event=$(latest_reachability_event)

while true; do
  if [ -f "$MODDIR/disable" ] || [ -f "$MODDIR/remove" ]; then
    log "module disabled or marked for removal"
    exit 0
  fi

  now=$(uptime_seconds)
  wifi_on=$(wifi_setting wifi_on)
  airplane=$(wifi_setting airplane_mode_on)
  sample_health

  if [ "$wifi_on" != "$last_wifi_on" ]; then
    grace_until=$((now + GRACE_SECONDS))
    bad_streak=0
    disconnected_since=0
    reachability_latched=0
    has_healthy=0
    healthy_bssid=
    last_wifi_on=$wifi_on
    last_reachability_event=$(latest_reachability_event)
  fi

  if [ -n "$SAMPLE_BSSID" ] && [ -n "$healthy_bssid" ] && [ "$SAMPLE_BSSID" != "$healthy_bssid" ]; then
    grace_until=$((now + GRACE_SECONDS))
    bad_streak=0
    disconnected_since=0
    reachability_latched=0
    has_healthy=0
    healthy_bssid=
    last_reachability_event=$(latest_reachability_event)
  fi

  if [ "$SAMPLE_SIGNATURE" != "$last_signature" ]; then
    grace_until=$((now + GRACE_SECONDS))
    bad_streak=0
    disconnected_since=0
    last_signature=$SAMPLE_SIGNATURE
  fi

  if [ "$SAMPLE_CLASSIFICATION" != healthy ] && [ "$now" -ge "$next_event_check" ]; then
    current_event=$(latest_reachability_event)
    next_event_check=$((now + 30))
    if [ -n "$current_event" ] && [ "$current_event" != "$last_reachability_event" ]; then
      reachability_latched=1
      last_reachability_event=$current_event
      log "new IP reachability failure latched"
    fi
  fi

  if ! policy_intent_allows_recovery "$wifi_on" "$airplane" "$SAMPLE_FRAMEWORK_ENABLED"; then
    bad_streak=0
    disconnected_since=0
    reachability_latched=0
    state="paused wifi_on=$wifi_on airplane=$airplane framework=$SAMPLE_FRAMEWORK_ENABLED"
  else
    case "$SAMPLE_CLASSIFICATION" in
      healthy)
        has_healthy=1
        healthy_bssid=$SAMPLE_BSSID
        bad_streak=0
        disconnected_since=0
        reachability_latched=0
        state="healthy iface=$SAMPLE_INTERFACE bssid=$SAMPLE_BSSID ip=$SAMPLE_IPV4 gateway=$SAMPLE_GATEWAY"
        ;;
      bad)
        bad_streak=$((bad_streak + 1))
        disconnected_since=0
        state="bad streak=$bad_streak iface=$SAMPLE_INTERFACE ip=$SAMPLE_IPV4 gateway=$SAMPLE_GATEWAY neigh=$SAMPLE_NEIGHBOR"
        ;;
      disconnected)
        bad_streak=0
        [ "$disconnected_since" -gt 0 ] || disconnected_since=$now
        disconnected_seconds=$((now - disconnected_since))
        state="disconnected seconds=$disconnected_seconds latched=$reachability_latched iface=$SAMPLE_INTERFACE"
        ;;
      *)
        bad_streak=0
        disconnected_since=0
        state="neutral iface=$SAMPLE_INTERFACE gateway=$SAMPLE_GATEWAY neigh=$SAMPLE_NEIGHBOR"
        ;;
    esac
  fi

  if [ "$state" != "$last_logged_state" ]; then
    log "$state"
    last_logged_state=$state
  fi
  last_classification=$SAMPLE_CLASSIFICATION

  grace_active=0
  [ "$now" -lt "$grace_until" ] && grace_active=1
  disconnected_seconds=0
  [ "$disconnected_since" -gt 0 ] && disconnected_seconds=$((now - disconnected_since))

  if policy_should_recover "$has_healthy" "$grace_active" "$SAMPLE_CLASSIFICATION" "$bad_streak" "$disconnected_seconds" "$reachability_latched"; then
    reason=$SAMPLE_CLASSIFICATION
    expected_event=
    [ "$reason" = disconnected ] && expected_event=$last_reachability_event
    perform_recovery "$reason" "$healthy_bssid" "$expected_event" || true
    bad_streak=0
    disconnected_since=0
    reachability_latched=0
    grace_until=$(( $(uptime_seconds) + GRACE_SECONDS ))
    last_signature=
    last_reachability_event=$(latest_reachability_event)
  fi

  interruptible_sleep "$CHECK_INTERVAL" || exit 0
done
