#!/usr/bin/env python3

from pathlib import Path
from sys import stderr


def process_lang_file(path: str) -> None:
    values = {}
    with open(path, "r", encoding="UTF-8") as fh:
        while line := fh.readline():
            vals = line.split("=")
            if len(vals) != 2:
                continue

            key = vals[0].strip()
            values[key] = vals[1].strip()

    with open(path, "w", encoding="UTF-8") as fh:
        for item in lang_strings:
            v = values.get(item)
            if v is not None:
                fh.write(f"{item} = {v}\n")
            else:
                fh.write("\n")


zig_lang_file = Path(__file__).parent.joinpath("../../src/config/Lang.zig").resolve()
if not zig_lang_file.exists():
    print(f"ERROR: File '{zig_lang_file.as_posix()}' does not exist. Exiting.", file=stderr)
    exit(1)

lang_strings = []
with open(zig_lang_file, "r", encoding="UTF-8") as fh:
    while line := fh.readline():
        lang_strings.append(line.split(":")[0])

lang_files = [f for f in Path.iterdir(Path(__file__).parent) if f.name.endswith(".ini") and f.is_file()]

for file in lang_files:
    process_lang_file(file.as_posix())
