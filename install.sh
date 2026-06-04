#!/bin/bash
# Auto Printer Server - Install Script
# Supports both online (apt-get) and offline (local .deb packages) installation

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "=== Installing Auto Printer Server ==="

# 1. Install dependencies (offline if packages/ present)
if [ -d "$SCRIPT_DIR/packages" ] && [ "$(ls $SCRIPT_DIR/packages/*.deb 2>/dev/null | wc -l)" -gt 0 ]; then
    echo ">>> Installing from local packages/ directory..."
    dpkg -i --no-debsig "$SCRIPT_DIR/packages"/*.deb 2>/dev/null || true
    # Fix any remaining dependency issues without downloading
    apt --fix-broken install --no-download -y 2>/dev/null || true
else
    echo ">>> Installing via apt-get (online)..."
    apt-get update -qq
    apt-get install -y -qq cups cups-filters brlaser printer-driver-brlaser \
        poppler-utils ghostscript python3 avahi-daemon 2>/dev/null
fi

# 2. Install center-filter.py
echo ">>> Installing center-filter.py..."
cp "$SCRIPT_DIR/scripts/center-filter.py" /usr/local/bin/center-filter.py
chmod +x /usr/local/bin/center-filter.py

# 3. Backup and install imagetoraster wrapper
echo ">>> Installing imagetoraster wrapper..."
if [ -f /usr/lib/cups/filter/imagetoraster ] && [ ! -f /usr/lib/cups/filter/imagetoraster.orig ]; then
    cp /usr/lib/cups/filter/imagetoraster /usr/lib/cups/filter/imagetoraster.orig
fi
cp "$SCRIPT_DIR/scripts/imagetoraster-wrapper.py" /usr/lib/cups/filter/imagetoraster
chmod +x /usr/lib/cups/filter/imagetoraster

# 4. Backup gstoraster
if [ -f /usr/lib/cups/filter/gstoraster ] && [ ! -f /usr/lib/cups/filter/gstoraster.orig ]; then
    cp /usr/lib/cups/filter/gstoraster /usr/lib/cups/filter/gstoraster.orig
fi

# 5. Fix BOM/CRLF (files may come from Windows)
echo ">>> Fixing line endings..."
for f in /usr/local/bin/center-filter.py /usr/lib/cups/filter/imagetoraster; do
    sed -i '1s/^\xef\xbb\xbf//' "$f" 2>/dev/null || true
    sed -i 's/\r$//' "$f" 2>/dev/null || true
done

# 6. Enable & restart services
echo ">>> Starting services..."
systemctl enable avahi-daemon cups 2>/dev/null
systemctl restart avahi-daemon cups 2>/dev/null
sleep 2

echo "=== Installation complete! ==="
echo ""
echo "Next steps:"
echo "  1. Connect USB printer to N1"
echo "  2. Printer auto-detection will handle USB printers automatically"
echo "  3. Or use web UI: http://armbian.local:631"
echo "  4. Share printer: cupsctl --share-printers; cupsctl --remote-any"
echo "  5. Print a photo from iPhone to test centering"
