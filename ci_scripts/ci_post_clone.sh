#!/bin/sh
# Xcode Cloud runs this right after cloning the repository.
#
# Config/Local.xcconfig is git-ignored, so the clone has no Class backend. This writes it from
# the workflow's environment variables (App Store Connect → Xcode Cloud → your workflow →
# Environment → Environment Variables):
#
#   SUPABASE_URL               https://<project-ref>.supabase.co
#   SUPABASE_PUBLISHABLE_KEY   the sb_publishable_… key (never the secret / service-role key)
#
# Optional, for a homework-only build:  ALLOW_ARCHIVE_WITHOUT_CLASS_BACKEND = YES
#
# The archive's "Check release configuration" build phase still validates the values.

set -eu

# Only on Xcode Cloud: never overwrite a developer's own Config/Local.xcconfig.
if [ "${CI:-}" != "TRUE" ] || [ -z "${CI_PRIMARY_REPOSITORY_PATH:-}" ]; then
    echo "Not running on Xcode Cloud; leaving Config/Local.xcconfig alone."
    exit 0
fi

target="$CI_PRIMARY_REPOSITORY_PATH/Config/Local.xcconfig"
url="${SUPABASE_URL:-}"
key="${SUPABASE_PUBLISHABLE_KEY:-}"

if [ -z "$url" ] || [ -z "$key" ]; then
    if [ "${ALLOW_ARCHIVE_WITHOUT_CLASS_BACKEND:-NO}" = "YES" ]; then
        printf '// Written by ci_scripts/ci_post_clone.sh\nALLOW_ARCHIVE_WITHOUT_CLASS_BACKEND = YES\n' > "$target"
        echo "No Class backend configured; homework-only build."
        exit 0
    fi
    echo "error: Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY in the Xcode Cloud workflow's environment variables."
    exit 1
fi

# xcconfig treats "//" as a comment, so "https://host" is written as "https:/$()/host".
escaped_url=$(printf '%s' "$url" | sed 's#://#:/$()/#')

{
    echo "// Written by ci_scripts/ci_post_clone.sh from Xcode Cloud environment variables."
    echo "SUPABASE_URL = $escaped_url"
    echo "SUPABASE_PUBLISHABLE_KEY = $key"
} > "$target"

host=$(printf '%s' "$url" | sed -E 's#^[a-z]+://##; s#/.*##')
echo "Wrote Config/Local.xcconfig for $host"
