#!/bin/bash
# Repeatable release checks and TestFlight archives for Homework Progress.
#
#   scripts/testflight.sh check                 all test suites + secret scan (no signing)
#   scripts/testflight.sh archive [--build N]   signed Release archive in build/
#   scripts/testflight.sh export  [--build N]   archive + App Store Connect .ipa in build/ (no upload)
#   scripts/testflight.sh upload  [--build N]   archive + upload to App Store Connect
#
# The build number defaults to the number of commits on HEAD, so it grows with every commit
# and never repeats for the same version. Pass --build N to choose it yourself. Signing uses
# the Apple ID signed in under Xcode → Settings → Accounts; nothing secret is read or stored
# by this script. Nothing is uploaded unless you run `upload`.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/Homework progress.xcodeproj"
SCHEME="Homework progress"
TEAM_ID="K36SNFAJDS"
OUT="$ROOT/build"

command="${1:-}"; shift || true
build_number=""
while [ $# -gt 0 ]; do
    case "$1" in
        --build) build_number="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 2 ;;
    esac
done
[ -n "$build_number" ] || build_number="$(git -C "$ROOT" rev-list --count HEAD)"

# The newest available iPhone simulator, by id, so the run doesn't depend on device names.
simulator_id() {
    xcrun simctl list devices available --json | python3 -c '
import json, sys
runtimes = json.load(sys.stdin)["devices"]
ios = sorted((r for r in runtimes if "iOS" in r), key=lambda r: [int(x) for x in r.split("iOS-")[1].split("-")], reverse=True)
for runtime in ios:
    for device in runtimes[runtime]:
        if device["name"].startswith("iPhone"):
            print(device["udid"]); sys.exit(0)
sys.exit("No iPhone simulator is installed (Xcode → Settings → Components).")'
}

run_checks() {
    local sim; sim="$(simulator_id)"
    echo "▸ Secret scan";                 python3 "$ROOT/scripts/secret-scan.py"
    echo "▸ StudyKit (swift test)";       (cd "$ROOT/Packages/StudyKit" && swift test)
    echo "▸ Database security (PGlite)";  (cd "$ROOT/tools/db-tests" && npm ci --silent && npm test && npm run test:edge)
    echo "▸ ClassroomUI";                 (cd "$ROOT/Packages/ClassroomUI" && xcodebuild test -scheme ClassroomUI \
                                              -destination "id=$sim" CODE_SIGNING_ALLOWED=NO -quiet)
    echo "▸ App unit tests";              xcodebuild test -project "$PROJECT" -scheme "$SCHEME" \
                                              -only-testing:"Homework progressTests" -destination "id=$sim" \
                                              CODE_SIGNING_ALLOWED=NO -quiet
    echo "✓ All checks passed"
}

archive() {
    if [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
        echo "warning: the working tree has uncommitted changes; the archive will include them."
    fi
    local version
    version="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null \
        | awk -F' = ' '/ MARKETING_VERSION = /{print $2; exit}')"
    ARCHIVE="$OUT/HomeworkProgress-$version-$build_number.xcarchive"
    echo "▸ Archiving version $version ($build_number) → $ARCHIVE"
    xcodebuild archive -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
        -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
        -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$build_number" -quiet
    echo "✓ Archive: $ARCHIVE"
}

export_archive() {
    local destination="$1"
    local options="$OUT/ExportOptions-$destination.plist"
    mkdir -p "$OUT"
    cat > "$options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>$destination</string>
	<key>teamID</key><string>$TEAM_ID</string>
	<key>signingStyle</key><string>automatic</string>
	<key>uploadSymbols</key><true/>
	<key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$options" \
        -exportPath "$OUT/export-$build_number" -allowProvisioningUpdates
}

case "$command" in
    check)   run_checks ;;
    archive) archive ;;
    export)  archive; export_archive export; echo "✓ IPA in $OUT/export-$build_number (not uploaded)" ;;
    upload)  archive; export_archive upload; echo "✓ Uploaded build $build_number. Processing takes 5–30 minutes in App Store Connect." ;;
    *) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
