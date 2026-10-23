#!/bin/bash
# Build phase "Check release configuration" (app target).
#
# Runs on every build but only enforces anything when archiving (ACTION=install), which is
# what TestFlight and App Store uploads are made from. An archive fails if the Class tab's
# backend is missing, local, a placeholder, or configured with a secret key.
#
# A homework-only build (no Class backend on purpose) can opt out by adding
#   ALLOW_ARCHIVE_WITHOUT_CLASS_BACKEND = YES
# to Config/Local.xcconfig.

set -u

[ "${ACTION:-}" = "install" ] || exit 0

fail() { echo "error: $1"; exit 1; }

url="${SUPABASE_URL:-}"
key="${SUPABASE_PUBLISHABLE_KEY:-}"

if [ -z "$url" ] || [ -z "$key" ]; then
    if [ "${ALLOW_ARCHIVE_WITHOUT_CLASS_BACKEND:-NO}" = "YES" ]; then
        echo "warning: Archiving without a Class backend: the Class tab will ask testers to connect one."
        exit 0
    fi
    fail "SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY are empty, so testers would get a Class tab that can't connect. Fill in Config/Local.xcconfig (see Config/Local.example.xcconfig), or set ALLOW_ARCHIVE_WITHOUT_CLASS_BACKEND = YES there for a homework-only build."
fi

case "$url" in
    https://*) ;;
    *) fail "SUPABASE_URL must be an https:// Supabase project for an archive (got a local or non-HTTPS address)." ;;
esac

for placeholder in your-project YOUR_ replace-me "<" example.supabase.co; do
    case "$url$key" in
        *"$placeholder"*) fail "Config/Local.xcconfig still contains the placeholder \"$placeholder\"." ;;
    esac
done

case "$key" in
    sb_secret_*) fail "SUPABASE_PUBLISHABLE_KEY is a SECRET key. Use the publishable key, and rotate the secret key in the Supabase dashboard." ;;
esac

# Legacy JWT keys: refuse the service_role one.
payload=$(printf '%s' "$key" | cut -d. -f2 | tr '_-' '/+')
while [ $(( ${#payload} % 4 )) -ne 0 ]; do payload="$payload="; done
if printf '%s' "$payload" | base64 -D 2>/dev/null | grep -q '"role" *: *"service_role"'; then
    fail "SUPABASE_PUBLISHABLE_KEY is the service_role key. Use the anon/publishable key, and rotate the service_role key."
fi

host="${url#https://}"; host="${host%%/*}"
echo "note: Archive uses the Class backend at $host"
