#!/bin/bash

set -eu

function process_lang_file() {
    local input_file=$1
    local -A lang_strings_in_file

    while read -r line; do
        if [[ -z "$line" ]]; then
            :
        elif [[ "$line" =~ ^([^\ ]*)[\ ]?\=[\ ]?(.*) ]]; then
            lang_strings_in_file["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
        else
            echo "ERROR: Line '$line' in file '$input_file' does not contain an entry of the pattern '<key> = <value>'. Exiting." >&2
            exit 1
        fi
    done < "$input_file"

    {
        for s in "${LANG_STRINGS[@]}"; do
            if [[ -v "lang_strings_in_file[\"$s\"]" ]]; then
                printf "%s = %s\n" "$s" "${lang_strings_in_file[$s]}"
            else
                printf "\n"
            fi
        done
    } > "$input_file"
}

LANG_DIR=$(dirname "$(realpath $0)")

ZIG_LANG_FILE=$(realpath "$LANG_DIR/../../src/config/Lang.zig")

if [ ! -f "$ZIG_LANG_FILE" ]; then
    echo "ERROR: File '$ZIG_LANG_FILE' does not exist. Exiting." >&2
    exit 1
fi

declare -a LANG_STRINGS

while read -r line; do
    if [[ "$line" =~ ^([^:]*): ]]; then
        LANG_STRINGS+=("${BASH_REMATCH[1]}")
    else
        echo "ERROR: Line '$line' in file '$ZIG_LANG_FILE' does not contain an entry of the pattern '<lang_item>: ...'." >&2
        exit 1
    fi
done < "$ZIG_LANG_FILE"

for file in $LANG_DIR/*.ini; do
    process_lang_file "$file"
done
