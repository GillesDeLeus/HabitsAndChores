#!/usr/bin/env python3
"""Merge model-generated translations into the String Catalog.

Not part of any build target. Used to apply a machine-translation pass to
HabitsAndChores/Resources/Localizable.xcstrings without hand-editing JSON.

Input: a JSON file mapping  { "<source key>": { "<lang>": "<translation>", ... }, ... }
Behaviour:
  * Adds/overwrites the stringUnit for each (key, lang) with state "translated".
  * Creates the localizations block / language entries if absent.
  * If a key is missing from the catalog entirely it is created (used to seed the
    runtime-only Templates.json strings, which Xcode's extractor cannot discover).
  * Existing entries for other languages are preserved untouched.
  * Idempotent: re-running with the same input is a no-op.

Usage:
  python3 scripts/merge_translations.py path/to/translations.json
  python3 scripts/merge_translations.py --seed-key "Source string" path/to/translations.json
"""
import json
import sys
import argparse

CATALOG = "HabitsAndChores/Resources/Localizable.xcstrings"
LANGS = ["fr", "nl", "it", "pl", "es", "de"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("translations", help="JSON file: {key: {lang: value}}")
    ap.add_argument("--catalog", default=CATALOG)
    args = ap.parse_args()

    with open(args.catalog, encoding="utf-8") as f:
        cat = json.load(f)
    strings = cat["strings"]

    with open(args.translations, encoding="utf-8") as f:
        trans = json.load(f)

    added_keys = 0
    written = 0
    for key, by_lang in trans.items():
        entry = strings.get(key)
        if entry is None:
            entry = {}
            strings[key] = entry
            added_keys += 1
        loc = entry.setdefault("localizations", {})
        for lang, value in by_lang.items():
            unit = loc.setdefault(lang, {}).setdefault("stringUnit", {})
            if unit.get("value") != value or unit.get("state") != "translated":
                written += 1
            unit["state"] = "translated"
            unit["value"] = value

    # Match Xcode's String Catalog formatting (2-space indent, " : " separators,
    # preserved key order) so diffs stay minimal and Xcode won't rewrite the file.
    with open(args.catalog, "w", encoding="utf-8") as f:
        json.dump(cat, f, ensure_ascii=False, indent=2, separators=(",", " : "))
        f.write("\n")

    print(f"merged {written} translation units across {len(trans)} keys "
          f"({added_keys} new keys created)")


if __name__ == "__main__":
    main()
