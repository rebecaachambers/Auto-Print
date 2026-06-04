
#!/bin/bash

source /etc/printer-auto.conf 2>/dev/null
# Auto Printer Detection System v1
# Triggers: udev (hotplug) + systemd path (boot) + systemd timer (periodic)
set -e

LOGFILE="/var/log/printer-auto.log"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE"; }

# ---- Step 1: Wait for USB printer device ----
sleep 4

USB_DEV=""
for d in /dev/usb/lp* /dev/lp*; do
    [ -c "$d" ] && { USB_DEV="$d"; break; }
done

if [ -z "$USB_DEV" ]; then
    log "No USB printer device found. Exiting."
    exit 1
fi
log "Found printer device: $USB_DEV"

# ---- Step 2: Get printer info from CUPS USB backend ----
USB_BACKEND=$(/usr/lib/cups/backend/usb 2>/dev/null | head -1)
USB_URI=$(lpinfo -v 2>/dev/null | grep "^direct usb" | head -1 | awk '"'"'{print $2}'"'"')
log "USB backend: $USB_BACKEND"
log "CUPS URI: $USB_URI"

if [ -z "$USB_URI" ]; then
    USB_URI="usb://$USB_DEV"
    log "Falling back to device URI: $USB_URI"
fi

# ---- Step 3: Extract brand and model from URI ----
# URI format: usb://BRAND/MODEL?serial=...
URI_PATH=$(echo "$USB_URI" | sed '"'"'s|usb://||'"'"' | sed '"'"'s|?.*||'"'"')
BRAND=$(echo "$URI_PATH" | cut -d/ -f1)
MODEL=$(echo "$URI_PATH" | cut -d/ -f2-)
log "Brand: $BRAND, Model: $MODEL"

# ---- Step 4: Check if printer already exists with correct driver ----
EXISTING=$(lpstat -p 2>/dev/null | grep "^printer" | awk '"'"'{print $2}'"'"')
for p in $EXISTING; do
    PPD=$(lpoptions -p "$p" 2>/dev/null | grep -oP "ppd-name:\S+" || true)
    # Check if existing printer uses the same device URI
    EXISTING_URI=$(lpstat -p "$p" -l 2>/dev/null | grep "device for" | sed '"'"'s/.*: //'"'"')
    if [ "$EXISTING_URI" = "$USB_URI" ]; then
        log "Printer $p already configured for this device. Skipping."
        exit 0
    fi
done

# ---- Step 5: Find the best matching driver ----
DRIVER=""

# Strategy A: Extract model number and search exact match
MODEL_NUM=$(echo "$MODEL" | grep -oP '"'"'[A-Z]*[-]?[0-9]+[A-Z]*'"'"' | head -1)
if [ -n "$MODEL_NUM" ]; then
    log "Searching driver for model: $MODEL_NUM"
    # Try exact model number match
    DRIVER=$(lpinfo -m 2>/dev/null | grep -i "$MODEL_NUM" | head -1 | cut -d" " -f1)
fi

# Strategy B: Match by brand + model number substring
if [ -z "$DRIVER" ] && [ -n "$BRAND" ] && [ -n "$MODEL_NUM" ]; then
    log "Trying brand+model match: $BRAND $MODEL_NUM"
    DRIVER=$(lpinfo -m 2>/dev/null | grep -i "$BRAND" | grep -i "$MODEL_NUM" | head -1 | cut -d" " -f1)
fi

# Strategy C: Match by brand only  
if [ -z "$DRIVER" ] && [ -n "$BRAND" ]; then
    log "Trying brand match: $BRAND"
    DRIVER=$(lpinfo -m 2>/dev/null | grep -i "^$BRAND" | head -1 | cut -d" " -f1)
    if [ -z "$DRIVER" ]; then
        DRIVER=$(lpinfo -m 2>/dev/null | grep -i "$BRAND" | head -1 | cut -d" " -f1)
    fi
fi

# Strategy D: Extract USB VID/PID and match via foomatic DB
if [ -z "$DRIVER" ]; then
    log "Trying USB VID/PID matching..."
    VID=$(echo "$USB_BACKEND" | awk '"'"'{print $2}'"'"' | cut -d: -f1 2>/dev/null)
    PID=$(echo "$USB_BACKEND" | awk '"'"'{print $3}'"'"' 2>/dev/null)
    # lsusb based approach
    USB_INFO=$(lsusb 2>/dev/null | grep -v "root hub" | head -1)
    DEVICE_NAME=$(echo "$USB_INFO" | sed '"'"'s/.*: //'"'"')
    log "USB device name: $DEVICE_NAME"
    DRIVER=$(lpinfo -m 2>/dev/null | grep -i "$DEVICE_NAME" | head -1 | cut -d" " -f1)
fi

# Strategy E: Driverless IPP Everywhere (for modern printers)
if [ -z "$DRIVER" ]; then
    log "Trying driverless IPP Everywhere"
    DRIVER="everywhere"
fi

# Strategy F: Raw queue (last resort - sends raw data, client must provide PPD)
if [ -z "$DRIVER" ] || [ "$DRIVER" = "raw" ]; then
    log "Last resort: raw queue"
    DRIVER="raw"
fi

log "Selected driver: $DRIVER"

# ---- Step 6: Add printer to CUPS ----
PRINTER_NAME="${BRAND}_${MODEL}" 
PRINTER_NAME=$(echo "$PRINTER_NAME" | sed '"'"'s/[^a-zA-Z0-9_-]/_/g'"'"')
PRINTER_NAME="${PRINTER_NAME:0:63}"

log "Adding printer: $PRINTER_NAME with driver $DRIVER"

if lpadmin -p "$PRINTER_NAME" -E -v "$USB_URI" -m "$DRIVER" -o printer-is-shared=true -o PageSize=A4 -o fit-to-page=true 2>> "$LOGFILE"; then
    sleep 2
    cupsenable "$PRINTER_NAME" 2>> "$LOGFILE"
    cupsaccept "$PRINTER_NAME" 2>> "$LOGFILE"
    lpadmin -d "$PRINTER_NAME" 2>> "$LOGFILE"
    log "SUCCESS: Printer $PRINTER_NAME added and shared"
else
    log "ERROR: Failed to add printer with driver $DRIVER"
fi
[?9001l[?1004l
