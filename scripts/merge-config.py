#!/usr/bin/env python3
"""
Merges config/overrides.json over the config.json the upstream image ships.

The image ships a fully written config.json, so every default our patches set
in Go is already spelled out in that file and never reached. Patching the Go
constant is still right for anyone building from source; this is what makes it
true for the image as well.

Usage: merge-config.py <upstream config.json> <overrides.json> <output>
"""

import json
import sys


def merge(base, over):
    for key, value in over.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            merge(base[key], value)
        else:
            base[key] = value
    return base


def main():
    base_path, over_path, out_path = sys.argv[1:4]
    with open(base_path) as f:
        base = json.load(f)
    with open(over_path) as f:
        over = json.load(f)
    with open(out_path, "w") as f:
        json.dump(merge(base, over), f, indent=4)
        f.write("\n")


if __name__ == "__main__":
    main()
