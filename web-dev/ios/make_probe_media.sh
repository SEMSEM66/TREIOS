#!/usr/bin/env bash
# make_probe_media.sh: the small test files of the app's compat probe, into web-dev/ios/build/probe-media
# (build_ipa.sh puts them in the app). Needs ffmpeg with libsvtav1, libx264, libx265 and libopus (Ubuntu's has them).
#
# Two kinds, so that what the probe reports is measured and not guessed:
#   made here    one movie per codec in the shape of the game's movies (1920x1080, 4:2:0, 8 bit, AAC sound):
#                AV1 as the game has it, and H.264 and HEVC as a fallback would be; one sound per container a
#                fallback could use (Ogg Opus as the game has it, then Opus in MP4, WebM and CAF, AAC, MP3);
#                an AVIF and a WebP picture.
#   from the game  TM_CI.mp4 (the logo movie, 0.5 MB), an interface sound, a standing picture and an interface
#                picture: the files the game will really ask WebKit to decode.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
assets="$here/../../web/assets"
out="$here/build/probe-media"
rm -rf "$out"; mkdir -p "$out"
ff() { ffmpeg -hide_banner -loglevel error -y "$@"; }

picture=(-f lavfi -i "testsrc2=size=1920x1080:rate=30:duration=3")
tone=(-f lavfi -i "sine=frequency=440:sample_rate=48000:duration=3")
sound=(-c:a aac -b:a 128k -ac 2)
ff "${picture[@]}" "${tone[@]}" -c:v libsvtav1 -preset 8 -crf 38 -pix_fmt yuv420p "${sound[@]}" -movflags +faststart "$out/av1.mp4"
ff "${picture[@]}" "${tone[@]}" -c:v libx264 -profile:v high -preset veryfast -crf 24 -pix_fmt yuv420p "${sound[@]}" -movflags +faststart "$out/h264.mp4"
ff "${picture[@]}" "${tone[@]}" -c:v libx265 -preset veryfast -crf 26 -pix_fmt yuv420p -tag:v hvc1 -x265-params log-level=error "${sound[@]}" -movflags +faststart "$out/hevc.mp4"

tone1=(-f lavfi -i "sine=frequency=660:sample_rate=48000:duration=1")
ff "${tone1[@]}" -ac 2 -c:a libopus -b:a 96k "$out/opus.ogg"
ff "${tone1[@]}" -ac 2 -c:a libopus -b:a 96k "$out/opus.webm"
ff "${tone1[@]}" -ac 2 -c:a libopus -b:a 96k -strict -2 "$out/opus.mp4"
ff "${tone1[@]}" -ac 2 -c:a libopus -b:a 96k "$out/opus.caf"
ff "${tone1[@]}" -ac 2 -c:a aac -b:a 128k "$out/aac.m4a"
ff "${tone1[@]}" -ac 2 -c:a libmp3lame -b:a 128k "$out/mp3.mp3"

ff -f lavfi -i "testsrc2=size=256x256:rate=1:duration=1" -frames:v 1 -c:v libaom-av1 -still-picture 1 -crf 30 -pix_fmt yuv420p "$out/image.avif"
ff -f lavfi -i "testsrc2=size=256x256:rate=1:duration=1" -frames:v 1 -c:v libwebp -quality 80 "$out/image.webp"

# The game's own files, where the checkout has them.
copy() { if [ -f "$1" ]; then cp "$1" "$out/$2"; else echo "not in this checkout: $1" >&2; fi; }
copy "$assets/movie/TM_CI.mp4" game-av1.mp4
copy "$assets/sys/0.ogg" game-opus.ogg
copy "$assets/img/AKI_A_00_00_N01.avif" game-picture.avif
copy "$assets/ui/TITLE_PARTS_JA/press_start.webp" game-ui.webp

for f in "$out"/*; do
    printf '%8d  %-18s %s\n' "$(wc -c <"$f")" "$(basename "$f")" \
        "$(ffprobe -v error -show_entries stream=codec_name,profile,width,height,pix_fmt,r_frame_rate,sample_rate,channels -of csv=p=0 "$f" 2>/dev/null | tr '\n' ' ')"
done
