#!/usr/bin/env python3
"""
Affinity Thumbnailer — KDE/Dolphin için .afphoto/.afdesign/.afpub thumbnail çıkarıcı.
Kullanım: affinity_thumbnailer.py <input_file> <output_png> <size>
Affinity binary formatındaki gömülü PNG thumbnail'i çıkarır ve ölçekler.
"""
import sys
import struct
import os

def find_png(data):
    """Binary veriden ilk PNG bloğunu bul ve döndür."""
    idx = data.find(b'\x89PNG\r\n\x1a\n')
    if idx < 0:
        return None
    # IEND chunk'ını bul (PNG sonu)
    iend = data.find(b'IEND', idx)
    if iend < 0:
        return None
    return data[idx:iend + 8]  # IEND + 4-byte CRC


def find_jpeg(data):
    """Binary veriden ilk JPEG bloğunu bul."""
    idx = data.find(b'\xff\xd8\xff')
    if idx < 0:
        return None
    end = data.find(b'\xff\xd9', idx)
    if end < 0:
        return None
    return data[idx:end + 2]


def main():
    if len(sys.argv) < 4:
        print(f"Kullanım: {sys.argv[0]} <giriş> <çıkış.png> <boyut>", file=sys.stderr)
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2]
    size = int(sys.argv[3])

    try:
        with open(input_file, 'rb') as f:
            data = f.read()
    except Exception as e:
        print(f"Dosya okunamadı: {e}", file=sys.stderr)
        sys.exit(1)

    # Thumbnail'i bul
    thumb_data = find_png(data) or find_jpeg(data)
    if not thumb_data:
        print("Thumbnail bulunamadı", file=sys.stderr)
        sys.exit(1)

    # PIL/Pillow ile ölçekle ve kaydet
    try:
        from PIL import Image
        import io
        img = Image.open(io.BytesIO(thumb_data))
        img.thumbnail((size, size), Image.LANCZOS)
        img.save(output_file, 'PNG')
        sys.exit(0)
    except ImportError:
        pass

    # Pillow yoksa ham PNG'yi direkt yaz (boyutu yoksay)
    with open(output_file, 'wb') as f:
        f.write(thumb_data)
    sys.exit(0)


if __name__ == '__main__':
    main()
