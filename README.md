# Wi-Fi Gateway Watchdog for Xiaomi Jaws

[Русская версия](README.ru.md)

A conservative Magisk watchdog for Xiaomi `MiTV-AFKR0` (`jaws`). It detects a confirmed loss of the local Wi-Fi gateway and requests Android 14's built-in Wi-Fi subsystem recovery.

The module was created for a failure where Wi-Fi remained formally enabled and associated, but Android reported `NUD_FAILED → LOST_PROVISIONING`, removed the device's IPv4 address, and sometimes did not recover until Wi-Fi was toggled manually.

## What it does

- waits for boot completion, then observes a boot/grace period;
- checks the active Wi-Fi association, IPv4 address, policy-routing gateway, gateway neighbor state, and a bounded local gateway probe;
- ignores old `NUD_FAILED` records in Wi-Fi history;
- after three consecutive confirmed gateway failures, calls only:

```sh
cmd wifi trigger-recovery
```

- confirms recovery with two successful gateway probes;
- records limited diagnostic snapshots;
- applies cooldown, burst limits, and failure lockout.

## What it does not do

The module does **not**:

- enable Wi-Fi when the user intentionally disabled it;
- use a direct Wi-Fi off/on sequence;
- change `Settings.Global.WIFI_ON`;
- unload drivers or rebind USB devices;
- restart Android services manually;
- reboot the device;
- modify ADB, USB host, firewall, routes, saved networks, or Wi-Fi power-save settings;
- test external Internet hosts.

## Compatibility

The installer intentionally accepts only:

- product device: `jaws`;
- SoC: `AMLS905X4`;
- Android firmware exposing `cmd wifi trigger-recovery`.

Tested on:

- Xiaomi `MiTV-AFKR0`;
- Android 14 / SDK 34;
- Magisk 31.1;
- SELinux enforcing;
- Wi-Fi interface `wlan0`, MediaTek `mt7663_usb`;
- 5 GHz BSSID after recovery;
- ADB TCP + USB-host storage and the companion wakelock/power-save modules.

Do not bypass the compatibility check on other devices.

## Safety policy

Recovery is allowed only after a healthy baseline and confirmed local gateway loss.

- check interval: 15 seconds;
- boot delay: 60 seconds;
- grace after Wi-Fi/network identity changes: 120 seconds;
- trigger: three consecutive failed gateway samples, or a newly observed IP reachability failure followed by a persistent disconnected state;
- cooldown: 30 minutes;
- burst limit: two recoveries per six hours;
- failed-recovery lockout: six hours;
- recovery timeout: 120 seconds.

If Wi-Fi is intentionally off, in airplane-mode-off state, or framework state is ambiguous, the watchdog fails closed and does nothing.

## Installation

1. Download the installable ZIP and `SHA256SUMS` from the latest [GitHub release](https://github.com/sergej19882906/magisk-wifi-gateway-watchdog-jaws/releases/latest).
2. Verify the ZIP checksum.
3. Install it through **Magisk → Modules → Install from storage**.
4. Reboot.

Do not install GitHub's automatically generated **Source code** archive. Use the ZIP attached to the release.

## Verification

```sh
su -c 'cat /data/adb/modules/wifi_gateway_watchdog_jaws/service.log'
```

A healthy state looks like:

```text
healthy iface=wlan0 ... ip=... gateway=...
```

The installed process and lock can be checked with:

```sh
su -c 'cat /data/adb/modules/wifi_gateway_watchdog_jaws/service.pid'
su -c 'cat /data/adb/modules/wifi_gateway_watchdog_jaws/service.lock/pid'
```

## Observe-only mode

Create this marker to keep detection and snapshots but suppress recovery:

```sh
su -c 'touch /data/adb/modules/wifi_gateway_watchdog_jaws/observe_only'
```

Remove it to allow recovery again:

```sh
su -c 'rm /data/adb/modules/wifi_gateway_watchdog_jaws/observe_only'
```

The marker is checked immediately before the recovery action.

## Diagnostics and privacy

The module stores at most three snapshots:

```text
/data/adb/modules/wifi_gateway_watchdog_jaws/snapshots/
```

Each snapshot is capped at 256 KiB and mode `0600`. Logs are capped at 64 KiB with one rotated backup.

Snapshots can contain sensitive local network metadata such as SSID, BSSID, MAC addresses, local IP addresses, gateway, and timestamps. Review and redact them before sharing publicly.

## Disable and uninstall

Disable or remove the module through Magisk and reboot. The uninstall script only stops its own verified PID. It does not alter the user's persisted Wi-Fi state.

## Troubleshooting

### Recovery is suppressed

Check the service log for `cooldown`, `burst`, or `lockout`. These controls prevent recovery loops.

### Wi-Fi is enabled but no AP is available

Generic loss of association does not by itself trigger recovery. The watchdog is specifically designed for confirmed gateway/reachability failure after a healthy baseline.

### Internet is down but the gateway works

No recovery is triggered. Loss of `VALIDATED` alone may indicate WAN, DNS, captive portal, or ISP problems and is intentionally not treated as a local Wi-Fi fault.

## Build and test

Python 3 and a POSIX shell are the only host requirements:

```sh
sh tests/test_policy.sh
python scripts/build.py
python scripts/verify.py
```

Outputs:

```text
dist/magisk-wifi-gateway-watchdog-jaws-vX.Y.Z.zip
dist/SHA256SUMS
```

The release ZIP is byte-for-byte reproducible.

## License

[MIT](LICENSE) © 2026 sergej19882906
