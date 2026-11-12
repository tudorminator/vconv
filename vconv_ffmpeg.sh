#!/usr/bin/env bash

set -o pipefail

if (( $# != 2 )); then
    printf 'Usage: %s <inPath> <outPath>\n' "${0##*/}" >&2
    exit 2
fi

if ! command -v cygpath >/dev/null 2>&1; then
    printf 'This script requires Git Bash and its cygpath command.\n' >&2
    exit 1
fi
in_path=$(cygpath -u -- "$1") || exit 1
out_path=$(cygpath -u -- "$2") || exit 1

if [[ ! -d $in_path ]]; then
    printf 'Input directory does not exist: %s\n' "$in_path" >&2
    exit 1
fi

for command in ffmpeg ffprobe awk; do
    if ! command -v "$command" >/dev/null 2>&1; then
        printf 'Required command not found: %s\n' "$command" >&2
        exit 1
    fi
done

shopt -s nullglob nocaseglob
files=("$in_path"/*.mov "$in_path"/*.mp4)
shopt -u nocaseglob

if (( ${#files[@]} == 0 )); then
    printf 'No MOV or MP4 files found in %s\n' "$in_path"
    exit 0
fi

if ! mkdir -p -- "$out_path"; then
    printf 'Cannot create output directory: %s\n' "$out_path" >&2
    exit 1
fi

declare -A output_names
for file in "${files[@]}"; do
    name=${file##*/}
    output_name=${name%.*}.mp4
    key=${output_name,,}
    if [[ ${output_names[$key]+found} ]]; then
        printf 'Multiple input files would produce the same output: %s\n' "$output_name" >&2
        exit 1
    fi
    output_names[$key]=1
    if [[ -e $out_path/$output_name ]]; then
        printf 'Output already exists; refusing to overwrite: %s\n' "$out_path/$output_name" >&2
        exit 1
    fi
done

if ! encoders=$(ffmpeg -hide_banner -encoders 2>&1); then
    printf 'Cannot list FFmpeg encoders:\n%s\n' "$encoders" >&2
    exit 1
fi
for encoder in h264_nvenc libfdk_aac; do
    if ! grep -Eq "^[[:space:]]*[A-Z.]+[[:space:]]+$encoder[[:space:]]" <<< "$encoders"; then
        printf 'FFmpeg encoder not available: %s\n' "$encoder" >&2
        printf 'NVENC needs an NVIDIA GPU; afterburner requires an FFmpeg build with libfdk_aac.\n' >&2
        exit 1
    fi
done

log_file=$(mktemp) || exit 1
trap 'rm -f -- "$log_file"' EXIT

total=${#files[@]}
completed=0
failed=0
first_draw=1

draw_bar() {
    local percent=$1 filled empty i
    filled=$(( percent * 24 / 100 ))
    empty=$(( 24 - filled ))
    printf '\033[36m'
    for ((i = 0; i < filled; i++)); do printf '█'; done
    printf '\033[90m'
    for ((i = 0; i < empty; i++)); do printf '░'; done
    printf '\033[0m %3d%%' "$percent"
}

draw_progress() {
    local file_percent=$1 label=$2 global_percent
    global_percent=$(( (completed * 100 + file_percent) / total ))
    if (( ! first_draw )); then
        printf '\033[2A'
    fi
    first_draw=0
    printf '\r\033[2KOverall ['
    draw_bar "$global_percent"
    printf '] %d/%d processed\n' "$completed" "$total"
    printf '\r\033[2KCurrent ['
    draw_bar "$file_percent"
    printf '] %s\n' "$label"
}

for file in "${files[@]}"; do
    name=${file##*/}
    output=$out_path/${name%.*}.mp4
    draw_progress 0 "$name"

    duration=$(ffprobe -v error -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 -- "$file" 2>"$log_file")
    if [[ $? -ne 0 ]] || ! duration_us=$(awk -v d="$duration" \
        'BEGIN { if (d !~ /^[0-9]+([.][0-9]+)?$/ || d * 1000000 < 0.5) exit 1; printf "%.0f", d * 1000000 }'); then
        printf 'Cannot determine duration for %s\n' "$file" >&2
        if [[ -s $log_file ]]; then cat "$log_file" >&2; fi
        ((failed += 1, completed += 1))
        first_draw=1
        continue
    fi

    if ffmpeg -hide_banner -loglevel error -nostats -n -i "$file" \
        -map 0:v:0 -map '0:a:0?' \
        -c:v h264_nvenc -profile:v main -preset p7 -tune hq \
        -rc vbr -b:v 2500k -maxrate 3500k -bufsize 7000k \
        -c:a libfdk_aac -ac 1 -profile:a aac_he -b:a 128k -afterburner 1 \
        -progress pipe:1 "$output" 2>"$log_file" | {
            elapsed=0
            while IFS='=' read -r key value; do
                case $key in
                    out_time_us)
                        if [[ $value =~ ^[0-9]+$ ]]; then elapsed=$value; fi
                        ;;
                    progress)
                        percent=$(( elapsed * 100 / duration_us ))
                        if (( percent > 100 )); then percent=100; fi
                        draw_progress "$percent" "$name"
                        ;;
                esac
            done
        }; then
        ((completed += 1))
        draw_progress 0 "$name (finished)"
    else
        printf 'Conversion failed for %s; an incomplete output may remain: %s\n' "$file" "$output" >&2
        if [[ -s $log_file ]]; then cat "$log_file" >&2; fi
        ((failed += 1, completed += 1))
        first_draw=1
    fi
done

if (( failed )); then
    printf '%d of %d conversions failed.\n' "$failed" "$total" >&2
    exit 1
fi
printf 'Finished: %d file(s).\n' "$total"
