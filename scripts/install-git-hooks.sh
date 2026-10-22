#!/usr/bin/env bash
# Installs a pre-commit hook that blocks commits containing secrets or forbidden files.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
hook=.git/hooks/pre-commit
cat > "$hook" <<'HOOK'
#!/usr/bin/env bash
exec python3 scripts/secret-scan.py --staged
HOOK
chmod +x "$hook"
echo "Installed $hook"
