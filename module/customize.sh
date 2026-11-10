#!/system/bin/sh

DEVICE=$(/system/bin/getprop ro.product.device)
SOC=$(/system/bin/getprop ro.soc.model)

if [ "$DEVICE" != jaws ] || [ "$SOC" != AMLS905X4 ]; then
  abort "! Unsupported device: $DEVICE / $SOC"
fi

for path in \
  /system/bin/getprop /system/bin/settings /system/bin/cmd /system/bin/ip \
  /system/bin/iw /system/bin/ping /system/bin/timeout /system/bin/sleep \
  /system/bin/cat /system/bin/stat /system/bin/tail /system/bin/head \
  /system/bin/grep /system/bin/awk /system/bin/cut /system/bin/date \
  /system/bin/dumpsys /system/bin/logcat /system/bin/dmesg /system/bin/mv \
  /system/bin/rm /system/bin/chmod /system/bin/mkdir /system/bin/rmdir \
  /system/bin/tr /system/bin/id /system/bin/kill; do
  [ -x "$path" ] || abort "! Missing required command: $path"
done

/system/bin/cmd wifi help 2>&1 | /system/bin/grep -q "trigger-recovery" \
  || abort "! Wi-Fi recovery API is unavailable"

set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/lib/watchdog-policy.sh" 0 0 0644
