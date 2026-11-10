#!/system/bin/sh

MODDIR=${0%/*}
PID_FILE="$MODDIR/service.pid"
EXPECTED_PATH="$MODDIR/service.sh"

: > "$MODDIR/disable"
pid=$(/system/bin/cat "$PID_FILE" 2>/dev/null)
case "$pid" in
  *[!0-9]*|'') ;;
  *)
    cmdline=$(/system/bin/tr '\000' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
    case "$cmdline" in
      *"$EXPECTED_PATH"*)
        /system/bin/kill "$pid" 2>/dev/null || true
        remaining=20
        while [ "$remaining" -gt 0 ] && [ -e "/proc/$pid" ]; do
          /system/bin/sleep 1
          remaining=$((remaining - 1))
        done
        ;;
    esac
    ;;
esac

# The module never changes the persisted Wi-Fi intent.
