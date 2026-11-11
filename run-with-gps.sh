#!/bin/bash
# run-with-gps.sh - start WatchDogsGo using a specific GPS serial port.
#
# Why: the game reads its GPS from /tmp/gps-pty by default (a bridge that needs
# gpsd + gps-socat). If you have no gpsd and your GPS is wired straight to a serial
# port (for example the AIO board's built-in GPS on /dev/ttyS0), the game says
# "GPS not found". This points the game at the serial port directly.
#
# Usage (from anywhere):
#     bash run-with-gps.sh                      # /dev/ttyS0 at 9600 baud
#     bash run-with-gps.sh /dev/ttyAMA0         # different port
#     bash run-with-gps.sh /dev/ttyS0 115200    # different port and baud
#
# Put this file in your WatchDogsGo folder (next to run.sh). It changes nothing
# permanently; it only sets WDG_GPS_DEVICE and WDG_GPS_BAUD for this run.
# Make sure the WiFi bridge is already running, and that nothing else (such as a
# terminal running "cat /dev/ttyS0") is reading the GPS port.

DEV="${1:-/dev/ttyS0}"
BAUD="${2:-9600}"

cd "$(dirname "$(readlink -f "$0")")" || exit 1

if [ ! -f ./run.sh ]; then
  echo "run.sh not found in $(pwd). Put this file in your WatchDogsGo folder."
  exit 1
fi

if [ ! -e "$DEV" ]; then
  echo "$DEV does not exist. Serial ports on this machine:"
  ls -l /dev/ttyS* /dev/ttyAMA* /dev/ttyACM* /dev/ttyUSB* /dev/serial* 2>/dev/null
  exit 1
fi

echo "Starting WatchDogsGo with GPS on $DEV at $BAUD baud"
exec sudo WDG_GPS_DEVICE="$DEV" WDG_GPS_BAUD="$BAUD" ./run.sh /tmp/esp32-pty
