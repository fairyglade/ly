#!/usr/bin/env python3

from pathlib import Path
from sys import stderr


def process_lang_file(path: Path, lang_keys: list[str]) -> None:
    # read key-value-pairs from lang file into dict
    existing_entries = {}
    with open(path, "r", encoding="UTF-8") as fh:
        while line := fh.readline():
            try:
                key, value = line.split("=", 1)
                existing_entries[key.strip()] = value.strip()
            except ValueError:  # line does not contain '='
                continue

    # re-write current lang file with entries in order of occurence in `lang_keys`
    # and with empty lines for missing translations
    with open(path, "w", encoding="UTF-8") as fh:
        for item in lang_keys:
            try:
                fh.write(f"{item} = {existing_entries[item]}\n")
            except KeyError:  # no translation for `item` yet
                fh.write("\n")


def main() -> None:
    zig_lang_file = Path(__file__).parent.joinpath("../../src/config/Lang.zig").resolve()
    if not zig_lang_file.exists():
        print(f"ERROR: File '{zig_lang_file.as_posix()}' does not exist. Exiting.", file=stderr)
        exit(1)

    # read "language keys" from `zig_lang_file` into list
    lang_keys = []
    with open(zig_lang_file, "r", encoding="UTF-8") as fh:
        while line := fh.readline():
            # only process lines that are not empty or no comments
            if not (line.strip() == "" or line.startswith("//")):
                lang_keys.append(line.split(":")[0].strip())

    lang_files = [f for f in Path.iterdir(Path(__file__).parent) if f.name.endswith(".ini") and f.is_file()]

    for file in lang_files:
        process_lang_file(file, lang_keys)


if __name__ == "__main__":
    main()
