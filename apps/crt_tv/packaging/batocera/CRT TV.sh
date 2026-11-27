#!/bin/sh
# CRT TV for Batocera: turns folders of videos into TV channels.
#
# Getting out of it:
#   - START, then QUIT CRT TV in its menu
#   - hold SELECT + START (or HOME + START) for three seconds. This is
#     watched for by crt_tv_escape.py, separately from the program, so it
#     works even when the program is stuck or ignoring the controller.
#   - HOTKEY + START (Batocera's own hotkey service, when it is running)
#
# This script never leaves the console stuck: if CRT TV hasn't put a
# picture up within 25 seconds it is stopped, a second display mode is
# tried, and then control goes back to the Batocera menu.
#
# What happened is written to   /userdata/system/logs/crt_tv.log
# (from Windows:  <share>\batocera\system\logs\crt_tv.log)
#
# Optional settings file: /userdata/system/configs/crt_tv.conf
#   VIDEO=software     safest (default). VIDEO=hardware is faster.
#   BACKEND=auto       or x11, or wayland
#   GLFIX=auto         or on, or off. The NVIDIA picture fix (see below);
#                      auto turns it on when an NVIDIA driver is running.

APP="${CRT_TV_APP:-/userdata/roms/ports/crt_tv}"
LOG="${CRT_TV_LOG:-/userdata/system/logs/crt_tv.log}"
CONF="${CRT_TV_CONF:-/userdata/system/configs/crt_tv.conf}"
OUT="${TMPDIR:-/tmp}/crt_tv.$$.out"
READY_WAIT="${CRT_TV_READY_WAIT:-25}"

VIDEO=software
BACKEND=auto
GLFIX=auto
#   With the NVIDIA fix in use, three more switches (each on or off):
#   GLFIX_DESYNC=on    finished frames go straight to the screen
#   GLFIX_VSYNC=off    hand frames over in step with the screen's refresh
#   GLFIX_FINISH=off   wait for each frame to be fully drawn first
GLFIX_DESYNC=on
GLFIX_VSYNC=off
GLFIX_FINISH=off
[ -f "$CONF" ] && . "$CONF"

mkdir -p "$(dirname "$LOG")"
log() { echo "$*" >> "$LOG"; }

# Batocera has the mpv program but not the libmpv library the app is built
# on, so libmpv and the libraries it needs that Batocera lacks travel with
# the app in its lib folder. Everything else comes from the system.
LD_LIBRARY_PATH="$APP/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH
# Point the player at the bundled copy by its full path. Left to search by
# name it could pick up a second copy from the system, and two copies of
# libmpv in one program crash it.
if [ -f "$APP/lib/libmpv.so.2" ]; then
  LIBMPV_LIBRARY_PATH="$APP/lib/libmpv.so.2"
  export LIBMPV_LIBRARY_PATH
fi

# On NVIDIA cards under Wayland, this version of Flutter puts the picture
# a full screen down and to the left: only its top-right quarter shows, in
# the bottom-left corner. libcrtglfix.so (built from gl_fix_shim.c, which
# explains it) corrects the one wrong number as it goes to the driver.
USE_GLFIX=no
case "$GLFIX" in
  on) USE_GLFIX=yes ;;
  off) ;;
  *) [ -e /proc/driver/nvidia/version ] && USE_GLFIX=yes ;;
esac
[ -f "$APP/lib/libcrtglfix.so" ] || USE_GLFIX=no

{
  echo "=== CRT TV launcher $(date) ==="
  echo "settings: VIDEO=$VIDEO BACKEND=$BACKEND GLFIX=$GLFIX DESYNC=$GLFIX_DESYNC VSYNC=$GLFIX_VSYNC FINISH=$GLFIX_FINISH wait=${READY_WAIT}s"
  echo "NVIDIA picture fix: $USE_GLFIX ($(head -n 1 /proc/driver/nvidia/version 2>/dev/null || echo "no NVIDIA driver"))"
  echo "display: WAYLAND_DISPLAY=$WAYLAND_DISPLAY DISPLAY=$DISPLAY XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
  echo "scaling: GDK_SCALE=$GDK_SCALE GDK_DPI_SCALE=$GDK_DPI_SCALE"
  command -v wlr-randr >/dev/null 2>&1 && wlr-randr 2>/dev/null | grep -E "^[^ ]|current|Scale|Adaptive"
  # Whether the window manager is set to let full-screen programs tear.
  for f in /etc/xdg/labwc/rc.xml "$HOME/.config/labwc/rc.xml" /userdata/system/.config/labwc/rc.xml; do
    [ -f "$f" ] && echo "labwc $f: $(grep -i -E 'tearing|adaptiveSync' "$f" | tr -s ' ' | tr '\n' ' ')"
  done
  echo "system C library: $(ls /lib/libc.so.6 /lib64/libc.so.6 /usr/lib/libc.so.6 2>/dev/null | head -n 1) $(ldd --version 2>/dev/null | head -n 1)"
  for lib in libmpv.so.2 libgtk-3.so.0; do
    found=$(ls "$APP/lib/$lib" /usr/lib/$lib /usr/lib64/$lib /lib/$lib 2>/dev/null | head -n 1)
    echo "$lib: ${found:-MISSING}"
  done
  echo "bundled libraries: $(ls "$APP/lib" 2>/dev/null | wc -l)"
  echo "controllers: $(ls /dev/input/js* 2>/dev/null | tr '\n' ' ')"
  for pad in /dev/input/js*; do
    [ -e "$pad" ] || continue
    name=$(cat "/sys/class/input/$(basename "$pad")/device/name" 2>/dev/null)
    if [ -r "$pad" ]; then can=readable; else can="NOT READABLE"; fi
    echo "  $pad: ${name:-unnamed} ($can)"
  done
  # Every input device's name and the handlers (js0, event5...) it has.
  grep -E '^(N|H):' /proc/bus/input/devices 2>/dev/null | sed 's/^/  /'
  # Batocera's hotkey service (evmapy), which is meant to act on the .keys file.
  echo "hotkey service: $(ps aux 2>/dev/null | grep -i '[e]vmapy' | head -n 3 | tr -s ' ' | cut -c 1-200)"
  for f in /var/run/evmapy/* /run/evmapy/*; do
    [ -f "$f" ] && echo "  $f: $(head -c 600 "$f" | tr -d '\n' | tr -s ' ')"
  done
  ls -la "$(dirname "$0")"/*.keys 2>/dev/null | sed 's/^/  keys file: /'
  if command -v ldd >/dev/null 2>&1; then
    # Every library the app and its bundled libraries ask for must be found.
    missing=$(ldd "$APP/crt_tv" "$APP"/lib/*.so* 2>/dev/null | grep "not found" | sort -u)
    if [ -n "$missing" ]; then echo "LIBRARIES NOT FOUND:"; echo "$missing"; else echo "all libraries found"; fi
    # And the pieces of them it uses must actually be in the system's copies.
    unmet=$(ldd -r "$APP/lib/libmpv.so.2" 2>&1 | grep -E "undefined symbol|version .* not found" | sort -u | head -n 20)
    [ -n "$unmet" ] && echo "MISMATCHES WITH SYSTEM LIBRARIES:" && echo "$unmet"
  fi
} > "$LOG" 2>&1

if [ ! -x "$APP/crt_tv" ]; then
  chmod +x "$APP/crt_tv" 2>/dev/null
fi
if [ ! -f "$APP/crt_tv" ]; then
  log "CRT TV isn't installed at $APP"
  exit 1
fi

PID=""
stop_app() {
  [ -n "$PID" ] || return 0
  kill "$PID" 2>/dev/null
  sleep 2
  kill -9 "$PID" 2>/dev/null
  wait "$PID" 2>/dev/null
  PID=""
}
# What the program prints is copied into the log as it appears, and the log
# is pushed to the drive every few seconds, so that switching the console
# off at the wall doesn't lose it.
COPIER=""
start_copy() {
  tail -n +1 -f "$OUT" >> "$LOG" 2>/dev/null &
  COPIER=$!
}
stop_copy() {
  stop_escape
  [ -n "$COPIER" ] || return 0
  sleep 1
  kill "$COPIER" 2>/dev/null
  wait "$COPIER" 2>/dev/null
  COPIER=""
  sync
}
ESCAPE=""
start_escape() {
  if command -v python3 >/dev/null 2>&1 && [ -f "$APP/crt_tv_escape.py" ]; then
    python3 "$APP/crt_tv_escape.py" "$PID" >> "$LOG" 2>&1 &
    ESCAPE=$!
  else
    log "escape: not available (needs python3 and crt_tv_escape.py)"
  fi
}
stop_escape() {
  [ -n "$ESCAPE" ] || return 0
  kill "$ESCAPE" 2>/dev/null
  wait "$ESCAPE" 2>/dev/null
  ESCAPE=""
}
trap 'log "launcher told to stop"; stop_app; stop_escape; stop_copy; rm -f "$OUT"; exit 0' INT TERM HUP

# Starts CRT TV with one display backend ("" = let it choose). Returns 0
# if it got a picture up (and then ran until the user quit), 1 if not.
attempt() {
  backend="$1"
  log "--- trying: backend=${backend:-default} video=$VIDEO ---"
  : > "$OUT"
  (
    cd "$APP" || exit 1
    [ -n "$backend" ] && export GDK_BACKEND="$backend"
    [ "$VIDEO" = software ] && export CRT_TV_SOFTWARE_VIDEO=1
    if [ "$USE_GLFIX" = yes ]; then
      export CRT_TV_GL_FIX=offset CRT_TV_GL_STATS=1
      [ "$GLFIX_DESYNC" = on ] && export CRT_TV_GL_DESYNC=1
      [ "$GLFIX_VSYNC" = on ] && export CRT_TV_GL_VSYNC=1
      [ "$GLFIX_FINISH" = on ] && export CRT_TV_GL_FINISH=1
      export LD_PRELOAD="$APP/lib/libcrtglfix.so${LD_PRELOAD:+ $LD_PRELOAD}"
    fi
    CRT_TV_FULLSCREEN=1 CRT_TV_DIAG=1 exec ./crt_tv --fullscreen
  ) > "$OUT" 2>&1 &
  PID=$!
  start_copy
  start_escape

  waited=0
  while [ "$waited" -lt "$READY_WAIT" ]; do
    # The program can keep running with nothing on screen when it failed
    # to get a graphics surface. It says so; don't wait out the clock.
    if grep -qE "Failed to create platform view rendering surface|Could not determine GL version" "$OUT" 2>/dev/null; then
      log "no graphics with backend=${backend:-default}: stopping it"
      stop_app
      stop_copy
      return 1
    fi
    if grep -q CRT_TV_READY "$OUT" 2>/dev/null; then
      log "picture up after ${waited}s"
      while kill -0 "$PID" 2>/dev/null; do
        sync
        sleep 5
      done
      wait "$PID"
      code=$?
      PID=""
      stop_copy
      log "CRT TV closed (exit $code) at $(date)"
      return 0
    fi
    if ! kill -0 "$PID" 2>/dev/null; then
      wait "$PID"
      code=$?
      PID=""
      stop_copy
      log "it stopped by itself before showing a picture (exit $code)"
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done

  log "no picture after ${READY_WAIT}s: stopping it"
  stop_app
  stop_copy
  return 1
}

case "$BACKEND" in
  x11|wayland) ORDER="$BACKEND" ;;
  *)
    # Wayland first: on real Batocera hardware (NVIDIA) it's the one that
    # draws; the X11 path there can't get a graphics context.
    if [ -n "$DISPLAY" ] && [ -n "$WAYLAND_DISPLAY" ]; then ORDER="wayland x11"
    elif [ -n "$DISPLAY" ]; then ORDER="x11"
    elif [ -n "$WAYLAND_DISPLAY" ]; then ORDER="wayland"
    else ORDER="default"
    fi
    ;;
esac

result=1
for backend in $ORDER; do
  [ "$backend" = default ] && backend=""
  if attempt "$backend"; then
    result=0
    break
  fi
  # Closed by the user from the controller: that isn't a failed start.
  if grep -q "^escape: .* closing CRT TV" "$LOG" 2>/dev/null; then
    result=0
    break
  fi
done

[ "$result" -ne 0 ] && log "CRT TV could not start on this system. Returning to Batocera."
rm -f "$OUT"
exit "$result"
