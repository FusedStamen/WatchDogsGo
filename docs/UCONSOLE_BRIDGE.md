# uConsole WiFi + BLE bridge (FusedStamen fork)

`wdg_wifi_bridge.py` lets WatchDogsGo run on a ClockworkPi uConsole (or any Linux box with a USB WiFi adapter) without an ESP32. It pretends to be the ESP32 over a virtual serial port (a PTY) and does the scanning with the host's own adapters: `iw` for WiFi, `bleak` for Bluetooth LE.

This page covers setup and the problems people actually hit. It lives in its own file so it never conflicts with upstream README changes.

## Quick setup

Run from your WatchDogsGo folder (the one that contains `wdg_wifi_bridge.py`).

1. Find your adapter names:

   ```
   iw dev
   for h in /sys/class/bluetooth/hci*; do echo "$(basename $h) $(cat $h/address) -> $(readlink -f $h)"; done
   ```

   - The WiFi adapter you scan with is normally `wlan1`. `wlan0` (built in) is usually your internet connection, so leave it alone.
   - In the Bluetooth output, a path containing `usb` is the USB board (for example the AC1200 / MT7921). A path containing `serial` or `uart` is the built-in Bluetooth.

2. Install the services:

   ```
   sudo bash install-wdg-services.sh --iface wlan1 --bt-iface hci0
   ```

   Replace the names with yours. It sets up three things and starts them:

   | Service | What it does |
   | --- | --- |
   | `wlan1-up.service` | Brings the scan adapter up at boot |
   | `wlan1-watchdog.timer` | Re-ups the adapter every 30 seconds if it drops |
   | `wdg-wifi-bridge.service` | Runs the bridge, unblocks Bluetooth first, uses `--no-monitor` |

   Other options: `--sniffer-iface`, `--user`, `--no-start`, `--dry-run DIR`, `--uninstall`.

3. Launch the game:

   ```
   sudo ./run.sh /tmp/esp32-pty
   ```

Watch the bridge live with `journalctl -u wdg-wifi-bridge -f`.

## Troubleshooting

### A scan prints "scan results printed" with no networks

The bridge now logs the reason, and also sends the game a `scan warning: ...` line. Check the log:

```
journalctl -u wdg-wifi-bridge -n 60 --no-pager
```

Look for a line starting `Scan failed` or `iw scan error`. Common causes:

| Log says | Meaning | Fix |
| --- | --- | --- |
| `interface wlanX not found` | Wrong `--iface`, or the adapter dropped off USB | Check `iw dev` and `lsusb`; replug or reboot |
| `is in monitor mode, cannot scan` | The bridge was started without `--no-monitor` | Use `--no-monitor` (the installer does) |
| `Network is down (-100)` | Adapter is down | The bridge now brings it up and retries; the watchdog timer keeps it up |
| `Device or resource busy (-16)` | NetworkManager or wpa_supplicant is mid-scan | The bridge retries automatically |
| no error, still empty | No networks in range, or the adapter is not really scanning | Run `sudo iw dev wlan1 scan \| grep -c "^BSS"` by hand |

### Every network shows as OPEN

An old copy of the script. Current versions read the `RSN:` and `Authentication suites:` lines from `iw` and report WPA2, WPA3, WPA2/WPA3, WPA or WEP. To confirm you have the current one, search the file for `LAST_SCAN_ERROR`.

### BLE scan returns 0 devices, or the WiFi adapter drops when BLE starts

Bluetooth is probably soft-blocked, which causes timeouts that can reset the USB board (the MT7921 handles WiFi and Bluetooth on one USB device). Check:

```
rfkill list
```

If it says `Soft blocked: yes`, run `sudo rfkill unblock bluetooth`. The service already does this on every start. If you run the bridge by hand, do it first.

If you see `org.bluez.Error.InProgress`, something left a Bluetooth scan open. The service runs `bluetoothctl scan off` before starting for this reason.

Make sure `--bt-iface` matches the right controller. `hci0` and `hci1` can swap between machines.

### Two bridges running

Only one bridge can own the adapter and the PTY. Stop any manual run (Ctrl+C) before using the service, and check with `systemctl status wdg-wifi-bridge`.

## GPS ("Gps not found" in the game)

The game does not need gpsd. At startup (`watchdogs/gps_manager.py`) it picks a GPS port in this order:

1. If the environment variable `WDG_GPS_DEVICE` is set, it uses that port directly and does no probing.
2. Otherwise it checks `/tmp/gps-pty` (a gpsd bridge, only present if you set one up) for NMEA data.
3. Otherwise it scans `/dev/ttyUSB*`, `/dev/ttyACM*` and `/dev/ttyAMA*` at 9600 baud and uses the first one that outputs NMEA (`$GP...` or `$GN...`).

The scan does **not** include `/dev/ttyS0`. On some boards the built-in GPS (for example the AIO board's) shows up as `/dev/ttyS0`, so the game says "Gps not found" even though the GPS works fine.

**Check where your GPS is:**

```
ls -l /dev/ttyAMA* /dev/ttyS0 /dev/ttyACM* /dev/ttyUSB* /dev/serial0 2>/dev/null
sudo timeout 5 cat /dev/ttyS0
```

Swap in each port from the first command for `/dev/ttyS0`. The port that prints lines starting with `$GNGGA` or `$GPGGA` is your GPS. In the `GGA` line, the number after the longitude's `E` or `W` is the fix quality (0 means no fix, 1 or higher means a fix). Stop any such `cat` with Ctrl+C before starting the game, because two readers on one port steal data from each other.

**If it is on `ttyS0` (or any port the scan skips), tell the game directly:**

```
bash run-with-gps.sh /dev/ttyS0
```

`run-with-gps.sh` just sets `WDG_GPS_DEVICE` (and `WDG_GPS_BAUD`, default 9600) and starts `run.sh`. If the position is garbage, try another baud: `bash run-with-gps.sh /dev/ttyS0 115200`.

If your GPS is on a `ttyAMA*`, `ttyACM*` or `ttyUSB*` port, the game should find it by itself and no setup is needed.

## Notes

- The bridge needs root.
- BLE scanning needs the `bleak` package in the project's `.venv`.
- Handshake and sniffer features dispatch to `hs_capture.py` and `pkt_sniff.py` and need a second adapter (`--sniffer-iface`) that supports monitor mode.
- To remove the services: `sudo bash install-wdg-services.sh --uninstall`.
