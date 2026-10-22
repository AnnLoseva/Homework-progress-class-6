#!/usr/bin/env python3
"""Rebuilds WoodlandStudy/Resources/Localizable.xcstrings (English source + Hebrew).

Keys come from the .stringsdata files the Swift compiler writes during a build (the app
target) plus `String(localized:)` calls in Packages/StudyKit. Translations come from
scripts/localization/<language>.json, so they are reviewable in pull requests.

    xcodebuild build -project WoodlandStudy.xcodeproj -scheme WoodlandStudy \
      -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd CODE_SIGNING_ALLOWED=NO
    python3 scripts/update-string-catalog.py build/dd

Keys without a translation are listed so they can be added to the JSON file.
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "WoodlandStudy", "Resources", "Localizable.xcstrings")
LANGUAGES = ["he"]


def app_keys(derived_data):
    keys = set()
    pattern = os.path.join(derived_data, "Build", "Intermediates.noindex", "WoodlandStudy.build", "**", "*.stringsdata")
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
    keys = app_keys(sys.argv[1]) | package_keys()
    if not keys:
        sys.exit("No strings found. Build the app first with the given -derivedDataPath.")

    translations = {}
    for language in LANGUAGES:
        with open(os.path.join(ROOT, "scripts", "localization", f"{language}.json"), encoding="utf-8") as handle:
            translations[language] = json.load(handle)

    strings = {}
    missing = []
    for key in sorted(keys):
        localizations = {}
        for language in LANGUAGES:
            value = translations[language].get(key)
            if value is None:
                missing.append((language, key))
                continue
            localizations[language] = {"stringUnit": {"state": "translated", "value": value}}
        strings[key] = {"localizations": localizations} if localizations else {}

    catalog = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
    with open(CATALOG, "w", encoding="utf-8") as handle:
        json.dump(catalog, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")

    print(f"Wrote {len(strings)} strings to {os.path.relpath(CATALOG, ROOT)}")
    for language, key in missing:
        print(f"  missing {language}: {key!r}")
    unused = {lang: sorted(set(translations[lang]) - keys) for lang in LANGUAGES}
    for language, items in unused.items():
        for key in items:
            print(f"  unused {language} translation: {key!r}")


if __name__ == "__main__":
    main()
