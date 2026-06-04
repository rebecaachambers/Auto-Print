#!/bin/bash
# Auto Printer Server - Docker Entrypoint
set -e

# ????
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()  { echo -e "  ${GREEN}?${NC} $1"; }
info(){ echo -e "  ${CYAN}?${NC} $1"; }
warn(){ echo -e "  ${YELLOW}?${NC} $1"; }

echo ""
echo -e "${CYAN}??? Auto Printer Server ???${NC}"
echo ""

# ---- 1. ?? D-Bus?avahi ??? ----
info "?? D-Bus..."
mkdir -p /run/dbus
dbus-daemon --system 2>/dev/null && ok "D-Bus" || warn "D-Bus ????"

# ---- 2. ?? avahi-daemon ----
info "?? avahi-daemon..."
avahi-daemon -D --no-chroot 2>/dev/null && ok "avahi-daemon" || warn "avahi-daemon ????"

# ---- 3. ?? CUPS ----
info "?? CUPS..."
cupsd -f &
CUPS_PID=$!
sleep 2
if kill -0 $CUPS_PID 2>/dev/null; then
    ok "CUPS (PID: $CUPS_PID)"
    cupsctl --remote-any --share-printers 2>/dev/null || true
else
    warn "CUPS ????"
fi

# ---- 4. ??????? ----
info "?? USB ???..."
/usr/local/bin/printer-auto-detect.sh 2>/dev/null || true

# ---- 5. ?? USB ?????? udev? ----
info "?? USB ?????..."
(
    LAST_COUNT=$(ls /dev/usb/lp* /dev/lp* 2>/dev/null | wc -l)
    while true; do
        sleep 5
        CURR_COUNT=$(ls /dev/usb/lp* /dev/lp* 2>/dev/null | wc -l)
        if [ "$CURR_COUNT" -gt "$LAST_COUNT" ]; then
            info "????????????..."
            /usr/local/bin/printer-auto-detect.sh 2>/dev/null || true
        fi
        LAST_COUNT=$CURR_COUNT
    done
) &
MONITOR_PID=$!

echo ""
echo -e "${GREEN}??? ????? ???${NC}"
echo "  CUPS ????: http://localhost:631"
echo "  AirPrint: ?????? iPhone/Mac ????????"
echo ""

# ---- 6. ????????? ----
trap "kill $CUPS_PID $MONITOR_PID 2>/dev/null; exit 0" SIGTERM SIGINT
wait $CUPS_PID $MONITOR_PID 2>/dev/null
