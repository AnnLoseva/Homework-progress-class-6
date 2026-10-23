#!/usr/bin/env python3
"""Scans the repository for things that must never be published.

Checks tracked files, staged changes, and (by default) every commit in git history for:
Supabase secret / service-role keys, private keys, access tokens, non-local database URLs
with passwords, real .env files, signing material and database dumps.

    python3 scripts/secret-scan.py            # working tree + full history
    python3 scripts/secret-scan.py --staged   # only what is about to be committed

Exit code 1 when something is found. This is a safety net, not a guarantee: also enable
GitHub secret scanning and push protection (see SECURITY.md).
"""
import re
import subprocess
import sys

PATTERNS = {
    "Supabase secret key": r"sb_secret_[A-Za-z0-9_-]{10,}",
    # base64 of "service_role" appears inside the JWT payload in one of three alignments.
    "Supabase service_role JWT": r"eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]*(c2VydmljZV9yb2xl|NlcnZpY2Vfcm9sZ|zZXJ2aWNlX3JvbGU)[A-Za-z0-9_-]*\.[A-Za-z0-9_-]+",
    "Supabase personal access token": r"sbp_[a-f0-9]{40}",
    "Private key": r"-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----(?:\\n|\s)*[A-Za-z0-9+/]{40,}",
    "GitHub token": r"(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}",
    "AWS access key": r"AKIA[0-9A-Z]{16}",
    "Slack token": r"xox[baprs]-[A-Za-z0-9-]{10,}",
    "Database URL with password (non-local)": r"postgres(?:ql)?://[^:@/\s]+:[^@/\s]{6,}@(?!127\.0\.0\.1|localhost)[^\s\"']+",
}
FORBIDDEN_FILES = re.compile(
    r"(^|/)\.env$|(^|/)\.env\.(?!example$)[^/]+$|Config/Local\.xcconfig$|\.p8$|\.p12$|\.mobileprovision$"
    r"|\.provisionprofile$|\.cer$|\.dump$|\.sql\.gz$|woodland-study-export.*\.json$"
)
SELF = "scripts/secret-scan.py"


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, errors="replace", check=True).stdout


def scan(label, lines):
    found = []
    for line in lines:
        if SELF in line:
            continue
        for name, regex in PATTERNS.items():
            if re.search(regex, line):
                found.append(f"[{label}] {name}: {line.strip()[:150]}")
    return found


def main():
    staged = "--staged" in sys.argv
    problems = []
    if staged:
        files = git("diff", "--cached", "--name-only", "--diff-filter=ACM").split()
        problems += [f"[staged] forbidden file: {f}" for f in files if FORBIDDEN_FILES.search(f)]
        added = [l for l in git("diff", "--cached", "-U0").splitlines() if l.startswith("+")]
        problems += scan("staged", added)
    else:
        files = git("ls-files").split("\n")
        problems += [f"[tracked] forbidden file: {f}" for f in files if f and FORBIDDEN_FILES.search(f)]
        for path in filter(None, files):
            if path == SELF:
                continue
            try:
                with open(path, encoding="utf-8") as handle:
                    problems += scan(path, handle.read().splitlines())
            except (UnicodeDecodeError, FileNotFoundError, IsADirectoryError):
                continue  # binary files (images, fonts)
        if subprocess.run(["git", "rev-parse", "--verify", "HEAD"], capture_output=True).returncode == 0:
            history = [l for l in git("log", "--all", "-p", "--no-color").splitlines() if l.startswith("+")]
            problems += scan("history", history)
            names = set(git("log", "--all", "--name-only", "--format=").split())
            problems += [f"[history] forbidden file was committed: {f}" for f in sorted(names) if FORBIDDEN_FILES.search(f)]

    if problems:
        print("✗ Secret scan FAILED:")
        for problem in dict.fromkeys(problems):
            print("   ", problem)
        print("\nRemove the values, ROTATE any real key that was exposed, and rewrite history if it was committed (see SECURITY.md).")
        return 1
    print(f"✓ Secret scan passed ({'staged changes' if staged else 'tracked files and full history'}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
