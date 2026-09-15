#!/usr/bin/env bash

# Check if kdialog or zenity is available
if command -v kdialog >/dev/null 2>&1; then
    FILE=$(kdialog --getopenfilename "$HOME" "Desteklenen Belgeler (*.afphoto *.afdesign *.afpub *.png *.jpg *.jpeg *.svg *.psd *.pdf *.webp *.tiff)|Tüm Dosyalar (*)")
elif command -v zenity >/dev/null 2>&1; then
    FILE=$(zenity --file-selection --title="Affinity - Dosya Seçip İçe Aktarın" \
        --file-filter="Tüm Görseller ve Belgeler | *.afphoto *.afdesign *.afpub *.png *.jpg *.jpeg *.svg *.psd *.pdf *.webp *.tiff *.bmp" \
        --file-filter="Tüm Dosyalar | *")
fi

if [ -n "$FILE" ] && [ -e "$FILE" ]; then
    /home/ters/.affinity/run.sh "$FILE"
fi
