#!/bin/bash
# install-wdg-services.sh
# Sets up the systemd services that keep the WatchDogsGo WiFi bridge working
# on a uConsole (or any Pi-style Linux box with a USB WiFi adapter):
#
#   wlan1-up.service          brings the scan adapter up at boot
#   wlan1-watchdog.timer      re-ups the adapter every 30s if it drops
#   wdg-wifi-bridge.service   runs wdg_wifi_bridge.py, unblocks Bluetooth first
#
# Run it from the WatchDogsGo folder (the one containing wdg_wifi_bridge.py):
#     sudo bash install-wdg-services.sh
#
# Options (all optional, defaults in brackets):
#     --iface wlan1            WiFi adapter used for scanning   [wlan1]
#     --bt-iface hci0          Bluetooth adapter for BLE scans  [hci0]
#     --sniffer-iface wlan2    adapter for handshake/sniffer    [wlan2]
#     --user NAME              user that owns the WatchDogsGo folder [the user who ran sudo]
#     --no-start               install and enable but do not start now
#     --dry-run DIR            write the unit files into DIR and change nothing else
#     --uninstall              stop, disable and remove these services
#
# Find your adapter names first with:   iw dev     and     hciconfig   (or bluetoothctl list)
#
# Everything it does is printed. Unit files go to /etc/systemd/system/.

set -u

IFACE=wlan1
BT_IFACE=hci0
SNIFFER_IFACE=wlan2
RUN_USER="${SUDO_USER:-}"
START=1
DRY=""
UNINSTALL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --iface)          IFACE="$2"; shift 2 ;;
    --bt-iface)       BT_IFACE="$2"; shift 2 ;;
    --sniffer-iface)  SNIFFER_IFACE="$2"; shift 2 ;;
    --user)           RUN_USER="$2"; shift 2 ;;
    --no-start)       START=0; shift ;;
    --dry-run)        DRY="$2"; shift 2 ;;
    --uninstall)      UNINSTALL=1; shift ;;
    -h|--help)        sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

UNITDIR=/etc/systemd/system
[ -n "$DRY" ] && UNITDIR="$DRY"

if [ -z "$DRY" ] && [ "$(id -u)" -ne 0 ]; then
  echo "Please run with sudo:  sudo bash $0"
  exit 1
fi

if [ "$UNINSTALL" -eq 1 ]; then
  systemctl disable --now wdg-wifi-bridge.service wlan1-watchdog.timer wlan1-up.service 2>/dev/null
  rm -fv "$UNITDIR"/wdg-wifi-bridge.service "$UNITDIR"/wlan1-watchdog.service \
         "$UNITDIR"/wlan1-watchdog.timer "$UNITDIR"/wlan1-up.service
  systemctl daemon-reload
  echo "Removed."
  exit 0
fi

# ---- locate the WatchDogsGo folder -----------------------------------------
if [ -f ./wdg_wifi_bridge.py ]; then
  WDG_DIR="$(pwd)"
else
  echo "ERROR: wdg_wifi_bridge.py not found in $(pwd)."
  echo "cd into your WatchDogsGo folder and run this again."
  exit 1
fi

# ---- pick a python: the project venv if it exists, else system python3 -----
if [ -x "$WDG_DIR/.venv/bin/python3" ]; then
  PY="$WDG_DIR/.venv/bin/python3"
else
  PY="$(command -v python3)"
  echo "NOTE: no .venv found in $WDG_DIR, using $PY (BLE scanning needs the 'bleak' package)."
fi

# ---- sanity checks (warn only) ----------------------------------------------
[ -z "$DRY" ] && [ ! -e "/sys/class/net/$IFACE" ] && \
  echo "WARNING: $IFACE does not exist right now. Check names with:  iw dev"
[ -z "$RUN_USER" ] && RUN_USER="$(stat -c %U "$WDG_DIR")"
LOOT="$WDG_DIR/loot"

echo "Using:"
echo "  folder         $WDG_DIR"
echo "  python         $PY"
echo "  scan adapter   $IFACE"
echo "  bluetooth      $BT_IFACE"
echo "  sniffer        $SNIFFER_IFACE"
echo "  loot dir       $LOOT"
echo

mkdir -p "$UNITDIR"

cat > "$UNITDIR/wlan1-up.service" <<EOF
[Unit]
Description=Bring up $IFACE for wardriving
After=network.target sys-subsystem-net-devices-$IFACE.device
Wants=sys-subsystem-net-devices-$IFACE.device

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 2
ExecStart=/sbin/ip link set $IFACE up
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

cat > "$UNITDIR/wlan1-watchdog.service" <<EOF
[Unit]
Description=Ensure $IFACE stays up

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'ip link show $IFACE | grep -q "UP" || ip link set $IFACE up'
EOF

cat > "$UNITDIR/wlan1-watchdog.timer" <<EOF
[Unit]
Description=Check $IFACE every 30s

[Timer]
OnBootSec=30s
OnUnitActiveSec=30s

[Install]
WantedBy=timers.target
EOF

cat > "$UNITDIR/wdg-wifi-bridge.service" <<EOF
[Unit]
Description=WatchDogsGo WiFi + BLE Bridge
After=network.target bluetooth.service wlan1-up.service
Wants=wlan1-up.service

[Service]
ExecStartPre=/usr/sbin/rfkill unblock bluetooth
ExecStartPre=/bin/bash -c 'bluetoothctl scan off 2>/dev/null; sleep 3'
ExecStart=$PY $WDG_DIR/wdg_wifi_bridge.py --iface $IFACE --bt-iface $BT_IFACE --sniffer-iface $SNIFFER_IFACE --no-monitor --loot-dir $LOOT
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

if [ -n "$DRY" ]; then
  echo "Dry run: unit files written to $DRY (nothing enabled or started)."
  ls -l "$DRY"
  exit 0
fi

mkdir -p "$LOOT"
chown "$RUN_USER":"$RUN_USER" "$LOOT" 2>/dev/null

systemctl daemon-reload
systemctl enable wlan1-up.service wlan1-watchdog.timer wdg-wifi-bridge.service

if [ "$START" -eq 1 ]; then
  systemctl start wlan1-up.service wlan1-watchdog.timer
  systemctl restart wdg-wifi-bridge.service
  sleep 4
fi

echo
echo "== status"
systemctl is-active wlan1-up.service wlan1-watchdog.timer wdg-wifi-bridge.service
echo
echo "== adapter"
ip -br link show "$IFACE" 2>&1
rfkill list 2>&1 | head -12
echo
echo "== last bridge log lines"
journalctl -u wdg-wifi-bridge -n 15 --no-pager 2>&1
echo
echo "Done. The bridge now starts at boot. Launch the game with:  sudo ./run.sh /tmp/esp32-pty"
echo "To watch the bridge live:  journalctl -u wdg-wifi-bridge -f"
