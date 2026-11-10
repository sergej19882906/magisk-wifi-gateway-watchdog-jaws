# Wi-Fi Gateway Watchdog for Xiaomi Jaws

[English version](README.md)

Консервативный Magisk-watchdog для Xiaomi `MiTV-AFKR0` (`jaws`). Он обнаруживает подтверждённую потерю локального Wi-Fi-шлюза и запускает встроенное восстановление Wi-Fi subsystem в Android 14.

Модуль создан для сбоя, при котором Wi-Fi формально оставался включённым и ассоциированным, но Android фиксировал `NUD_FAILED → LOST_PROVISIONING`, удалял IPv4-адрес устройства и иногда не восстанавливался без ручного переключения Wi-Fi.

## Что делает модуль

- ждёт полной загрузки и выдерживает boot/grace interval;
- проверяет ассоциацию, IPv4, gateway из policy routing, neighbor state и локальный probe шлюза;
- игнорирует старые записи `NUD_FAILED` в истории Wi-Fi;
- после трёх подряд подтверждённых отказов вызывает только:

```sh
cmd wifi trigger-recovery
```

- подтверждает восстановление двумя успешными probe шлюза;
- сохраняет ограниченные диагностические снимки;
- использует cooldown, burst limit и lockout после неудачи.

## Чего модуль не делает

Модуль **не**:

- включает Wi-Fi, если пользователь намеренно его выключил;
- выполняет прямую последовательность Wi-Fi off/on;
- изменяет `Settings.Global.WIFI_ON`;
- выгружает драйверы и не переподключает USB;
- вручную перезапускает Android-сервисы;
- перезагружает устройство;
- изменяет ADB, USB-host, firewall, routes, сохранённые сети или Wi-Fi power save;
- проверяет внешние интернет-адреса.

## Совместимость

Установщик намеренно принимает только:

- product device: `jaws`;
- SoC: `AMLS905X4`;
- прошивку с `cmd wifi trigger-recovery`.

Проверено на:

- Xiaomi `MiTV-AFKR0`;
- Android 14 / SDK 34;
- Magisk 31.1;
- SELinux enforcing;
- `wlan0`, MediaTek `mt7663_usb`;
- 5‑ГГц подключении после восстановления;
- ADB TCP + USB-host накопителе и сопутствующих wakelock/power-save модулях.

Не обходите проверку совместимости на других устройствах.

## Политика безопасности

Recovery разрешён только после healthy baseline и подтверждённой потери локального шлюза.

- интервал проверки: 15 секунд;
- задержка после загрузки: 60 секунд;
- grace после смены Wi-Fi/network identity: 120 секунд;
- три подряд плохих sample либо новое reachability failure с устойчивым disconnected state;
- cooldown: 30 минут;
- максимум два recovery за 6 часов;
- lockout после неудачного recovery: 6 часов;
- тайм-аут восстановления: 120 секунд.

Если Wi-Fi намеренно выключен, запрещён airplane mode или состояние framework неоднозначно, watchdog ничего не делает.

## Установка

1. Скачайте устанавливаемый ZIP и `SHA256SUMS` из последнего [релиза GitHub](https://github.com/sergej19882906/magisk-wifi-gateway-watchdog-jaws/releases/latest).
2. Проверьте контрольную сумму ZIP.
3. Установите его через **Magisk → Модули → Установить из хранилища**.
4. Перезагрузитесь.

Не устанавливайте автоматически созданный GitHub-архив **Source code**. Используйте ZIP из релиза.

## Проверка

```sh
su -c 'cat /data/adb/modules/wifi_gateway_watchdog_jaws/service.log'
```

Healthy состояние выглядит так:

```text
healthy iface=wlan0 ... ip=... gateway=...
```

PID и singleton lock:

```sh
su -c 'cat /data/adb/modules/wifi_gateway_watchdog_jaws/service.pid'
su -c 'cat /data/adb/modules/wifi_gateway_watchdog_jaws/service.lock/pid'
```

## Режим observe-only

Создайте marker, чтобы оставить детектирование и snapshots, но запретить recovery:

```sh
su -c 'touch /data/adb/modules/wifi_gateway_watchdog_jaws/observe_only'
```

Удалите marker для возврата автоматического recovery:

```sh
su -c 'rm /data/adb/modules/wifi_gateway_watchdog_jaws/observe_only'
```

Marker проверяется непосредственно перед recovery.

## Диагностика и приватность

Модуль хранит не более трёх snapshots:

```text
/data/adb/modules/wifi_gateway_watchdog_jaws/snapshots/
```

Каждый snapshot ограничен 256 КиБ и имеет права `0600`. Журнал ограничен 64 КиБ с одной резервной копией.

Snapshots могут содержать SSID, BSSID, MAC-адреса, локальные IP, gateway и временные метки. Перед публикацией их необходимо проверить и обезличить.

## Отключение и удаление

Отключите или удалите модуль через Magisk и перезагрузитесь. Uninstall-скрипт останавливает только проверенный собственный PID и не меняет сохранённое пользовательское состояние Wi-Fi.

## Решение проблем

### Recovery подавлен

Проверьте журнал на `cooldown`, `burst` или `lockout`. Эти ограничения предотвращают циклы восстановления.

### Wi-Fi включён, но точка доступа недоступна

Обычная потеря ассоциации сама по себе не запускает recovery. Watchdog предназначен только для подтверждённой потери gateway/reachability после healthy baseline.

### Интернет не работает, но шлюз доступен

Recovery не запускается. Потеря `VALIDATED` может означать проблему WAN, DNS, captive portal или провайдера, а не локальный сбой Wi-Fi.

## Сборка и тесты

Требуются Python 3 и POSIX shell:

```sh
sh tests/test_policy.sh
python scripts/build.py
python scripts/verify.py
```

Результаты:

```text
dist/magisk-wifi-gateway-watchdog-jaws-vX.Y.Z.zip
dist/SHA256SUMS
```

Release ZIP побайтово воспроизводим.

## Лицензия

[MIT](LICENSE) © 2026 sergej19882906
