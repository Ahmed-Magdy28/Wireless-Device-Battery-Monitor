#!/bin/sh
# Builds an Ubuntu/Debian .deb package in dist/ for wireless-battery.
# Usage: ./linux/build-deb.sh [version]
set -e

cd "$(dirname "$0")/.."

if [ -n "$1" ]; then
    VERSION="$1"
elif [ -n "${VERSION:-}" ]; then
    VERSION="$VERSION"
else
    TAG=$(git describe --tags --abbrev=0 2>/dev/null || true)
    case "$TAG" in
        v*) VERSION="${TAG#v}" ;;
        "") VERSION="1.0.0" ;;
        *)  VERSION="$TAG" ;;
    esac
fi

ARCH=$(dpkg --print-architecture)
PKG_NAME="wireless-battery"
STAGE="build/deb/${PKG_NAME}_${VERSION}_${ARCH}"
OUT_DEB="dist/${PKG_NAME}_${VERSION}_${ARCH}.deb"

./build-linux.sh

rm -rf "$STAGE"
mkdir -p \
    "$STAGE/DEBIAN" \
    "$STAGE/usr/bin" \
    "$STAGE/usr/share/applications" \
    "$STAGE/usr/share/icons/hicolor/scalable/apps" \
    "$STAGE/usr/lib/udev/rules.d" \
    "$STAGE/usr/share/doc/${PKG_NAME}" \
    dist

install -m 0755 wireless-battery "$STAGE/usr/bin/wireless-battery"
if command -v strip >/dev/null 2>&1; then
    strip --strip-unneeded "$STAGE/usr/bin/wireless-battery"
fi

install -m 0644 linux/wireless-battery.desktop "$STAGE/usr/share/applications/wireless-battery.desktop"
install -m 0644 linux/wireless-battery.svg "$STAGE/usr/share/icons/hicolor/scalable/apps/wireless-battery.svg"
install -m 0644 linux/99-wireless-battery.rules "$STAGE/usr/lib/udev/rules.d/99-wireless-battery.rules"
install -m 0644 LICENSE "$STAGE/usr/share/doc/${PKG_NAME}/copyright"

SHLIBS=""
if command -v dpkg-shlibdeps >/dev/null 2>&1; then
    # dpkg-shlibdeps expects debian/control in the current directory or -T/-l; pass -O and parse shlibs:Depends.
    mkdir -p "$STAGE/debian"
    touch "$STAGE/debian/control"
    SHLIBS=$(cd "$STAGE" && dpkg-shlibdeps -O usr/bin/wireless-battery 2>/dev/null | sed -n 's/^shlibs:Depends=//p' || true)
    rm -rf "$STAGE/debian"
fi

if [ -n "$SHLIBS" ]; then
    DEPENDS="$SHLIBS, udev"
else
    DEPENDS="libglib2.0-0t64 | libglib2.0-0, libcairo2, udev"
fi

INSTALLED_SIZE=$(du -sk "$STAGE/usr" | awk '{print $1}')

cat > "$STAGE/DEBIAN/control" <<EOF
Package: ${PKG_NAME}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${ARCH}
Installed-Size: ${INSTALLED_SIZE}
Depends: ${DEPENDS}
Recommends: gnome-shell-extension-appindicator | gnome-shell-extension-ubuntu-appindicators
Maintainer: Wireless Battery Contributors <https://github.com/krisgfx9/Wireless-Device-Battery-Monitor>
Homepage: https://github.com/krisgfx9/Wireless-Device-Battery-Monitor
Description: Wireless device battery monitor for the system tray
 Shows battery levels of wireless mice, keyboards, headsets, and gamepads
 in the system tray using hidraw and StatusNotifierItem.
EOF

cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = "configure" ]; then
    if command -v udevadm >/dev/null 2>&1; then
        udevadm control --reload-rules || true
        udevadm trigger --subsystem-match=hidraw || true
    fi
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
    fi
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database -q /usr/share/applications || true
    fi
fi
exit 0
EOF
chmod 0755 "$STAGE/DEBIAN/postinst"

cat > "$STAGE/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
    if command -v udevadm >/dev/null 2>&1; then
        udevadm control --reload-rules || true
        udevadm trigger --subsystem-match=hidraw || true
    fi
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
    fi
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database -q /usr/share/applications || true
    fi
fi
exit 0
EOF
chmod 0755 "$STAGE/DEBIAN/postrm"
chmod 0755 "$STAGE" "$STAGE/DEBIAN"
find "$STAGE/usr" -type d -exec chmod 0755 {} +

dpkg-deb --root-owner-group --build "$STAGE" "$OUT_DEB"
echo "Built $OUT_DEB"
