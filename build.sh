#!/bin/bash
# MicrophonePicker'ı derleyip çalıştırılabilir bir .app paketi haline getirir.
#
#   ./build.sh            → MicrophonePicker.app oluşturur
#   ./build.sh --install  → ayrıca /Applications içine kopyalar ve başlatır
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="MicrophonePicker"
BUNDLE="$APP_NAME.app"
INSTALL_PATH="/Applications/$BUNDLE"

echo "▸ Derleniyor (release)…"
swift build -c release

BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"
if [[ ! -x "$BINARY" ]]; then
	echo "✗ Derleme çıktısı bulunamadı: $BINARY" >&2
	exit 1
fi

echo "▸ Paketleniyor: $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BINARY" "$BUNDLE/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"

# Ad-hoc imza: girişte başlatma (SMAppService) sabit bir imza kimliği ister.
codesign --force --sign - --timestamp=none "$BUNDLE" >/dev/null 2>&1 ||
	echo "! Ad-hoc imzalama başarısız oldu; uygulama yine de çalışır ama 'Girişte Başlat' sorun çıkarabilir."

if [[ "${1:-}" == "--install" ]]; then
	echo "▸ Kuruluyor: $INSTALL_PATH"
	# Çalışan bir kopya varsa önce kapat, yoksa kopyalama başarısız olur.
	pkill -x "$APP_NAME" 2>/dev/null || true
	sleep 0.5
	rm -rf "$INSTALL_PATH"
	cp -R "$BUNDLE" "$INSTALL_PATH"
	open "$INSTALL_PATH"
	echo "✓ Kuruldu ve başlatıldı. Menü çubuğundaki mikrofon simgesine bakın."
else
	echo "✓ Hazır: $(pwd)/$BUNDLE"
	echo "  Başlatmak için:  open $BUNDLE"
	echo "  Kurmak için:     ./build.sh --install"
fi
