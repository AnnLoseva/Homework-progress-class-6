#!/usr/bin/env python3
"""Adds new keys and the Hebrew translations to "Homework progress/Localizable.xcstrings".

Keys come from the .stringsdata files the Swift compiler writes during a build (the app and
the ClassroomUI package) plus `String(localized:)` calls in Packages/StudyKit. Translations come from
scripts/localization/<language>.json, so they are reviewable in pull requests. Existing
entries (and their comments) are kept; nothing is removed.

    xcodebuild build -project "Homework progress.xcodeproj" -scheme "Homework progress" \
      -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd CODE_SIGNING_ALLOWED=NO
    python3 scripts/update-string-catalog.py build/dd

Keys of the Class area without a translation are listed so they can be added to the JSON
file. The homework screens are English-only for now.
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "Homework progress", "Localizable.xcstrings")
LANGUAGES = ["he"]


def built_keys(derived_data, target):
    keys = set()
    pattern = os.path.join(derived_data, "Build", "Intermediates.noindex", "**", f"{target}.build", "**", "*.stringsdata")
    for path in glob.glob(pattern, recursive=True):
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
        for entries in data.get("tables", {}).values():
            keys.update(entry["key"] for entry in entries)
    return keys


def package_keys():
    keys = set()
    for path in glob.glob(os.path.join(ROOT, "Packages", "StudyKit", "Sources", "**", "*.swift"), recursive=True):
        with open(path, encoding="utf-8") as handle:
            source = handle.read()
        for literal in re.findall(r'String\(localized: "((?:[^"\\]|\\.)*)"', source):
            # \(expression) interpolations become %@ in the key.
            keys.add(re.sub(r"\\\((?:[^()]|\([^()]*\))*\)", "%@", literal))
    return keys


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    class_keys = built_keys(sys.argv[1], "ClassroomUI") | package_keys()
    keys = built_keys(sys.argv[1], "Homework progress") | class_keys
    if not class_keys:
        sys.exit("No strings found. Build the app first with the given -derivedDataPath.")

    translations = {}
    for language in LANGUAGES:
        with open(os.path.join(ROOT, "scripts", "localization", f"{language}.json"), encoding="utf-8") as handle:
            translations[language] = json.load(handle)

    with open(CATALOG, encoding="utf-8") as handle:
        catalog = json.load(handle)
    strings = catalog.setdefault("strings", {})
    missing = []
    for key in sorted(keys):
        entry = strings.setdefault(key, {})
        for language in LANGUAGES:
            value = translations[language].get(key)
            if value is None:
                if key in class_keys:
                    missing.append((language, key))
                continue
            entry.setdefault("localizations", {})[language] = {"stringUnit": {"state": "translated", "value": value}}

    with open(CATALOG, "w", encoding="utf-8") as handle:
        json.dump(catalog, handle, ensure_ascii=False, indent=2, sort_keys=True, separators=(",", " : "))
        handle.write("\n")

    print(f"{len(strings)} strings in {os.path.relpath(CATALOG, ROOT)}")
    for language, key in missing:
        print(f"  missing {language}: {key!r}")
    unused = {lang: sorted(set(translations[lang]) - keys) for lang in LANGUAGES}
    for language, items in unused.items():
        for key in items:
            print(f"  unused {language} translation: {key!r}")


if __name__ == "__main__":
    main()
