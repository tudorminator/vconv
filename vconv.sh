#!/usr/bin/env bash

set -o pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

usage() {
    printf 'Usage: %s -i|--in <inPath> -o|--out <outPath> [-s|--size <scalePercent>] [-p|--preset <presetName>]\n' "${0##*/}" >&2
}

in_raw=""
out_raw=""
preset_name=""
scale_arg=""
scale_specified=0

while (( $# > 0 )); do
    case "$1" in
        -i|--in)
            if (( $# < 2 )); then
                printf 'Option %s requires an argument.\n' "$1" >&2
                usage
                exit 2
            fi
            in_raw="$2"
            shift 2
            ;;
        --in=*)
            in_raw="${1#*=}"
            shift
            ;;
        -o|--out)
            if (( $# < 2 )); then
                printf 'Option %s requires an argument.\n' "$1" >&2
                usage
                exit 2
            fi
            out_raw="$2"
            shift 2
            ;;
        --out=*)
            out_raw="${1#*=}"
            shift
            ;;
        -s|--size|--scale)
            if (( $# < 2 )); then
                printf 'Option %s requires an argument.\n' "$1" >&2
                usage
                exit 2
            fi
            scale_arg="$2"
            scale_specified=1
            shift 2
            ;;
        --size=*|--scale=*)
            scale_arg="${1#*=}"
            scale_specified=1
            shift
            ;;
        -p|--preset)
            if (( $# < 2 )); then
                printf 'Option %s requires an argument.\n' "$1" >&2
                usage
                exit 2
            fi
            preset_name="$2"
            shift 2
            ;;
        --preset=*)
            preset_name="${1#*=}"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            if (( $# > 0 )); then
                printf 'Positional parameters are not accepted: %s\n' "$1" >&2
                usage
                exit 2
            fi
            break
            ;;
        -*)
            printf 'Unknown option: %s\n' "$1" >&2
            usage
            exit 2
            ;;
        *)
            printf 'Positional parameters are not accepted: %s\n' "$1" >&2
            usage
            exit 2
            ;;
    esac
done

if [[ -z "$in_raw" ]] || [[ -z "$out_raw" ]]; then
    usage
    exit 2
fi

if (( scale_specified )); then
    scale_arg=${scale_arg%%%}
    if ! [[ "$scale_arg" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        printf 'Resize percentage must be a number, got: %s\n' "$scale_arg" >&2
        exit 2
    fi
else
    scale_arg=100
fi

preset_name=${preset_name:-"HEVC"}
preset_clean=$(basename -- "$preset_name")
preset_clean="${preset_clean%%.*}"

preset_file=""
for cand in \
    "$script_dir/${preset_clean}.preset.py" \
    "$preset_clean.preset.py" \
    "$preset_name" \
    "$script_dir/$preset_name"
do
    if [[ -f "$cand" ]]; then
        preset_file="$cand"
        break
    fi
done

if [[ -z "$preset_file" ]]; then
    printf 'Preset file not found: %s.preset.py\n' "$preset_clean" >&2
    exit 1
fi

preset_template=$(< "$preset_file") || exit 1

if ! command -v cygpath >/dev/null 2>&1; then
    printf 'This script requires Git Bash and its cygpath command.\n' >&2
    exit 1
fi

in_path=$(cygpath -u -- "$in_raw") || exit 1
out_path=$(cygpath -u -- "$out_raw") || exit 1
in_path=${in_path%/}
out_path=${out_path%/}

if [[ ! -e "$in_path" ]]; then
    printf 'Input path does not exist: %s\n' "$in_path" >&2
    exit 1
fi

if command -v exiftool >/dev/null 2>&1; then
    exiftool_bin=$(command -v exiftool)
elif [[ -e 'C:/Users/Tudor/Apps/exiftool/exiftool.exe' ]]; then
    exiftool_bin='C:/Users/Tudor/Apps/exiftool/exiftool.exe'
elif [[ -e '/c/Users/Tudor/Apps/exiftool/exiftool.exe' ]]; then
    exiftool_bin='/c/Users/Tudor/Apps/exiftool/exiftool.exe'
else
    exiftool_bin=''
fi

if ! command -v ffprobe >/dev/null 2>&1; then
    printf 'Required command not found: ffprobe\n' >&2
    exit 1
fi

avidemux_bin=''
for candidate in \
    'C:/Program Files/Avidemux/avidemux_cli.exe' \
    'C:/Program Files/Avidemux/avidemux.exe' \
    'C:/Program Files (x86)/Avidemux/avidemux_cli.exe' \
    'C:/Program Files (x86)/Avidemux/avidemux.exe' \
    $(command -v avidemux_cli 2>/dev/null) \
    $(command -v avidemux 2>/dev/null) \
    $(command -v avidemux3_cli 2>/dev/null)
do
    if [[ -n "$candidate" ]] && [[ -x "$candidate" || -e "$candidate" ]]; then
        avidemux_bin="$candidate"
        break
    fi
done

if [[ -z "$avidemux_bin" ]]; then
    printf 'Required command not found: avidemux_cli.exe or avidemux.exe\n' >&2
    exit 1
fi

if [[ -d "$in_path" ]]; then
    shopt -s nullglob nocaseglob
    files=("$in_path"/*.mov "$in_path"/*.mp4 "$in_path"/*.m4v)
    shopt -u nocaseglob
elif [[ -f "$in_path" ]]; then
    files=("$in_path")
else
    printf 'Input path is neither a directory nor a file: %s\n' "$in_path" >&2
    exit 1
fi

if (( ${#files[@]} == 0 )); then
    printf 'No MOV, MP4, or M4V files found in %s\n' "$in_path" >&2
    exit 0
fi

if ! mkdir -p -- "$out_path"; then
    printf 'Cannot create output directory: %s\n' "$out_path" >&2
    exit 1
fi

shopt -s nullglob
temp_leftovers=("$out_path"/vconv_tmp_*.mp4 "$out_path"/~*.mp4)
shopt -u nullglob
if (( ${#temp_leftovers[@]} > 0 )); then
    rm -f -- "${temp_leftovers[@]}"
fi

declare -A output_names
for file in "${files[@]}"; do
    if [[ ! -f "$file" ]]; then
        continue
    fi
    file_name=${file##*/}
    output_name=${file_name%.*}.mp4
    key=${output_name,,}
    if [[ ${output_names[$key]+found} ]]; then
        printf 'Multiple input files would produce the same output: %s\n' "$output_name" >&2
        exit 1
    fi
    output_names[$key]=1
done

resolve_rotation_code() {
    local raw="${1:-0}"
    raw=${raw%%.*}
    raw=${raw//[[:space:]]/}
    raw=${raw,,}
    raw=${raw#rotate}
    raw=${raw#cw}
    raw=${raw#ccw}
    raw=$(printf '%s' "$raw" | tr -cd '0-9')
    local normalized=${raw:-0}
    case "$normalized" in
        0|1) printf '0' ;;
        90|6) printf '1' ;;
        180|2|3) printf '2' ;;
        270|8) printf '3' ;;
        *) printf '0' ;;
    esac
}

scale_ratio=$(awk -v p="$scale_arg" 'BEGIN { if (p <= 0 || p > 100) exit 1; printf "%.12f", p / 100.0 }') || {
    printf 'Resize percentage must be between 1 and 100, got: %s\n' "$scale_arg" >&2
    exit 2
}

total=${#files[@]}
completed=0
failed=0
first_draw=1

draw_bar() {
    local percent=$1 width=${2:-24} color=${3:-36} out_var=${4:-REPLY}
    local filled=$(( percent * width / 100 ))
    local empty=$(( width - filled ))
    local f_str="" e_str=""
    if (( filled > 0 )); then printf -v f_str '%*s' "$filled" ''; f_str=${f_str// /█}; fi
    if (( empty > 0 )); then printf -v e_str '%*s' "$empty" ''; e_str=${e_str// /░}; fi
    printf -v "$out_var" '\033[%sm%s%s\033[0m %3d%%' "$color" "$f_str" "$e_str" "$percent"
}

get_terminal_cols() {
    local c
    c=$(tput cols 2>/dev/null)
    if [[ "$c" =~ ^[0-9]+$ ]] && (( c > 0 )); then
        echo "$c"
        return
    fi
    if [[ -n "${COLUMNS:-}" && "$COLUMNS" =~ ^[0-9]+$ ]] && (( COLUMNS > 0 )); then
        echo "$COLUMNS"
        return
    fi
    echo 80
}

term_cols=$(get_terminal_cols)
trap 'term_cols=$(get_terminal_cols)' WINCH

draw_progress() {
    local file_percent=$1 label=$2
    local bar_width prefix_len max_label_len display_label="$label"
    local current_num=$(( completed + 1 ))
    if (( current_num > total )); then current_num=$total; fi

    local global_percent=$(( completed * 100 / total ))

    if (( total > 1 )); then
        # Line 1 & Line 2: "Overall " / "Current " (8) + bar (W) + " " (1) + "%3d%%" (4) = W + 13
        bar_width=$(( term_cols - 13 - 1 ))
        if (( bar_width < 10 )); then bar_width=10; fi

        # Line 3: "Processing: X / Y | "
        local p_prefix="Processing: ${current_num} / ${total} | "
        prefix_len=${#p_prefix}
        max_label_len=$(( term_cols - prefix_len - 1 ))
        if (( max_label_len < 10 )); then max_label_len=10; fi

        if [[ "$label" == *" (finished)" ]]; then
            local suffix=" (finished)"
            local base="${label%" (finished)"}"
            if (( ${#label} > max_label_len )); then
                local avail=$(( max_label_len - ${#suffix} ))
                if (( avail > 3 )); then
                    display_label="${base:0:avail-3}...${suffix}"
                elif (( avail > 0 )); then
                    display_label="${base:0:avail}${suffix}"
                else
                    display_label="${label:0:max_label_len}"
                fi
            fi
        else
            if (( ${#label} > max_label_len )); then
                if (( max_label_len > 3 )); then
                    display_label="${label:0:max_label_len-3}..."
                else
                    display_label="${label:0:max_label_len}"
                fi
            fi
        fi

        local bar_o="" bar_c=""
        draw_bar "$global_percent" "$bar_width" 35 bar_o
        draw_bar "$file_percent" "$bar_width" 36 bar_c

        local buf=""
        if (( ! first_draw )); then
            buf+=$'\033[3A'
        fi
        first_draw=0
        buf+=$'\r\033[KOverall '"${bar_o}"$'\n'
        buf+=$'\r\033[KCurrent '"${bar_c}"$'\n'
        buf+=$'\r\033[K'"${p_prefix}"$'\033[33m'"${display_label}"$'\033[0m\n'
        printf '%s' "$buf"
    else
        # Single-file mode: Line 1 = bar (W) + " " (1) + "%3d%%" (4) = W + 5
        bar_width=$(( term_cols - 5 - 1 ))
        if (( bar_width < 10 )); then bar_width=10; fi

        max_label_len=$(( term_cols - 1 ))
        if (( max_label_len < 10 )); then max_label_len=10; fi

        if [[ "$label" == *" (finished)" ]]; then
            local suffix=" (finished)"
            local base="${label%" (finished)"}"
            if (( ${#label} > max_label_len )); then
                local avail=$(( max_label_len - ${#suffix} ))
                if (( avail > 3 )); then
                    display_label="${base:0:avail-3}...${suffix}"
                elif (( avail > 0 )); then
                    display_label="${base:0:avail}${suffix}"
                else
                    display_label="${label:0:max_label_len}"
                fi
            fi
        else
            if (( ${#label} > max_label_len )); then
                if (( max_label_len > 3 )); then
                    display_label="${label:0:max_label_len-3}..."
                else
                    display_label="${label:0:max_label_len}"
                fi
            fi
        fi

        local bar_c=""
        draw_bar "$file_percent" "$bar_width" 36 bar_c

        local buf=""
        if (( ! first_draw )); then
            buf+=$'\033[2A'
        fi
        first_draw=0
        buf+=$'\r\033[K'"${bar_c}"$'\n'
        buf+=$'\r\033[K\033[33m'"${display_label}"$'\033[0m\n'
        printf '%s' "$buf"
    fi
}

current_script_file=''
current_temp_output=''
current_adm_log=''
cleanup() {
    printf '\033[?25h'
    [[ -n "$current_script_file" && -f "$current_script_file" ]] && rm -f -- "$current_script_file"
    [[ -n "$current_temp_output" && -f "$current_temp_output" ]] && rm -f -- "$current_temp_output"
    [[ -n "$current_adm_log" && -f "$current_adm_log" ]] && rm -f -- "$current_adm_log"
}

on_interrupt() {
    trap - INT TERM EXIT
    cleanup
    printf '\nAborted by user.\n' >&2
    exit 130
}
trap on_interrupt INT TERM
trap cleanup EXIT

printf '\033[?25l'

for file in "${files[@]}"; do
    if [[ ! -f "$file" ]]; then
        continue
    fi

    file_name=${file##*/}
    output_name=${file_name%.*}.mp4
    output_file="$out_path/$output_name"

    if [[ -e "$output_file" ]]; then
        ((completed += 1))
        continue
    fi

    term_cols=$(get_terminal_cols)
    temp_output_file=$(mktemp -u -p "$out_path" --suffix=.mp4 vconv_tmp_XXXXXX) || exit 1

    draw_progress 0 "$file_name"

    source_width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 -- "$file" 2>/dev/null | awk 'NF {print; exit}')
    source_height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 -- "$file" 2>/dev/null | awk 'NF {print; exit}')

    if [[ ! "$source_width" =~ ^[0-9]+$ ]] || [[ ! "$source_height" =~ ^[0-9]+$ ]]; then
        printf '\nUnable to detect video dimensions for %s\n' "$file" >&2
        ((failed += 1, completed += 1))
        first_draw=1
        continue
    fi

    local_rotation=0
    if [[ -n "$exiftool_bin" ]]; then
        exif_rotation=$("$exiftool_bin" -s3 -n -Rotation -Orientation -- "$file" 2>/dev/null | awk 'NF {print; exit}')
        if [[ -n "$exif_rotation" ]]; then
            local_rotation=$(resolve_rotation_code "$exif_rotation")
        fi
    fi

    file_scale_width=$(awk -v w="$source_width" -v r="$scale_ratio" 'BEGIN { val = int(w * r + 0.5); if (val % 2 != 0) val = val + 1; printf "%d", val }')
    file_scale_height=$(awk -v h="$source_height" -v r="$scale_ratio" 'BEGIN { val = int(h * r + 0.5); if (val % 2 != 0) val = val + 1; printf "%d", val }')

    windows_file=$(cygpath -m -- "$file") || exit 1
    windows_temp_output=$(cygpath -m -- "$temp_output_file") || exit 1
    windows_file=${windows_file//\"/\\\"}
    windows_temp_output=${windows_temp_output//\"/\\\"}

    script_file=$(mktemp --suffix=.py)
    adm_log=$(mktemp) || exit 1
    current_script_file="$script_file"
    current_temp_output="$temp_output_file"
    current_adm_log="$adm_log"

    script_content="$preset_template"
    # Primary variables
    script_content="${script_content//\$\{INPUT_FILE\}/$windows_file}"
    script_content="${script_content//\$INPUT_FILE/$windows_file}"
    script_content="${script_content//\{\{INPUT_FILE\}\}/$windows_file}"

    script_content="${script_content//\$\{OUTPUT_FILE\}/$windows_temp_output}"
    script_content="${script_content//\$OUTPUT_FILE/$windows_temp_output}"
    script_content="${script_content//\{\{OUTPUT_FILE\}\}/$windows_temp_output}"

    script_content="${script_content//\$\{SCALE_WIDTH\}/$file_scale_width}"
    script_content="${script_content//\$SCALE_WIDTH/$file_scale_width}"
    script_content="${script_content//\{\{SCALE_WIDTH\}\}/$file_scale_width}"

    script_content="${script_content//\$\{SCALE_HEIGHT\}/$file_scale_height}"
    script_content="${script_content//\$SCALE_HEIGHT/$file_scale_height}"
    script_content="${script_content//\{\{SCALE_HEIGHT\}\}/$file_scale_height}"

    script_content="${script_content//\$\{ROTATION\}/$local_rotation}"
    script_content="${script_content//\$ROTATION/$local_rotation}"
    script_content="${script_content//\{\{ROTATION\}\}/$local_rotation}"

    # Additional contextual variables & backwards compatibility
    script_content="${script_content//\$\{SOURCE_WIDTH\}/$source_width}"
    script_content="${script_content//\$\{SOURCE_HEIGHT\}/$source_height}"
    script_content="${script_content//\$\{SCALE_PERCENT\}/$scale_arg}"
    script_content="${script_content//\$\{windows_file\}/$windows_file}"
    script_content="${script_content//\$\{windows_temp_output\}/$windows_temp_output}"
    script_content="${script_content//\$\{file_scale_width\}/$file_scale_width}"
    script_content="${script_content//\$\{file_scale_height\}/$file_scale_height}"
    script_content="${script_content//\$\{local_rotation\}/$local_rotation}"

    if (( ! scale_specified )); then
        filtered_content=""
        while IFS= read -r s_line || [[ -n "$s_line" ]]; do
            if [[ "$s_line" != *swscale* && "$s_line" != *msharpen* && "$s_line" != *[Ss]harpen* ]]; then
                filtered_content+="${s_line}"$'\n'
            fi
        done <<< "$script_content"
        script_content="$filtered_content"
    fi

    printf '%s\n' "$script_content" > "$script_file"

    last_percent=-1
    "$avidemux_bin" --run "$script_file" --quit 2>&1 | while IFS= read -r line; do
        line=${line%$'\r'}
        printf '%s\n' "$line" >> "$adm_log"
        if [[ "$line" =~ ^[[:space:]]*([0-9]+)% ]]; then
            percent=${BASH_REMATCH[1]}
            if (( percent != last_percent )); then
                last_percent=$percent
                draw_progress "$percent" "$file_name"
            fi
        fi
    done
    adm_status=${PIPESTATUS[0]}
    if (( adm_status == 130 || adm_status == 2 )); then
        on_interrupt
    fi

    file_size=0
    if [[ -f "$temp_output_file" ]]; then
        file_size=$(wc -c < "$temp_output_file" 2>/dev/null || stat -c%s "$temp_output_file" 2>/dev/null || echo 0)
    fi

    if (( adm_status != 0 || file_size < 10240 )); then
        printf '\nAvidemux conversion failed for %s\n' "$file" >&2
        if [[ -s "$adm_log" ]]; then
            err_lines=$(grep -E -i 'error|exception|fail' "$adm_log" || true)
            if [[ -n "$err_lines" ]]; then
                printf '%s\n' "$err_lines" >&2
            else
                tail -n 10 "$adm_log" >&2
            fi
        fi
        rm -f -- "$script_file" "$temp_output_file" "$adm_log"
        current_script_file=''
        current_temp_output=''
        current_adm_log=''
        ((failed += 1, completed += 1))
        first_draw=1
        continue
    fi

    rm -f -- "$script_file" "$adm_log"
    current_script_file=''
    current_adm_log=''
    mv -f -- "$temp_output_file" "$output_file" || {
        printf '\nFailed to rename temporary output file to %s\n' "$output_file" >&2
        rm -f -- "$temp_output_file"
        current_temp_output=''
        ((failed += 1, completed += 1))
        first_draw=1
        continue
    }
    current_temp_output=''
    ((completed += 1))
    if (( total > 1 )); then
        draw_progress 0 "$file_name (finished)"
    else
        draw_progress 100 "$file_name (finished)"
    fi
done

printf '\033[?25h'

if (( failed )); then
    printf '\n%d of %d conversions failed.\n' "$failed" "$total" >&2
    exit 1
fi
printf '\nFinished: %d file(s).\n' "$total"
