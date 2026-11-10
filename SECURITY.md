# Security Policy

## Supported versions

Only the latest GitHub release is supported with security fixes.

## Reporting a vulnerability

Please report security issues privately through [GitHub Security Advisories](https://github.com/sergej19882906/magisk-wifi-gateway-watchdog-jaws/security/advisories/new).

Do not attach unredacted snapshots, Wi-Fi credentials, ADB keys, private keys, device serials, proprietary firmware images, or full system dumps. Include the module version, Android build family, Magisk version, and minimum reproduction steps.

## Scope

The module runs as root during Magisk's late-start stage. Its only Wi-Fi mutation is Android's built-in `cmd wifi trigger-recovery`. It does not write Wi-Fi settings, modify saved networks, unload drivers, change routes, restart services manually, reboot, alter ADB/USB, or probe external Internet hosts.

Unexpected recovery while Wi-Fi is intentionally off, bypass of cooldown/lockout, arbitrary command execution, unsafe behavior on unsupported boards, unbounded diagnostics, or leakage of credentials is in scope.

## Diagnostic privacy

Snapshots are mode `0600`, bounded, and rotated, but can contain local network metadata such as SSID, BSSID, MAC addresses, local IP addresses, gateway and timestamps. Treat every snapshot as sensitive and redact it before sharing.
