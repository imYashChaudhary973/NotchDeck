#!/usr/bin/env bash
#
# NotchDeck developer environment diagnostics.
#
# Read-only: reports on the toolchain and repository state.
# It never modifies files, Git state or system settings.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_ROOT/NotchDeck.xcodeproj"
EXPECTED_REMOTE_PATTERN="github.com[:/]imYashChaudhary973/NotchDeck(\.git)?$"

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; }
section() { printf '\n\033[1m%s\033[0m\n' "$1"; }

problems=0

section "System"
if [[ "$(uname -s)" == "Darwin" ]]; then
    ok "macOS $(sw_vers -productVersion) ($(uname -m))"
else
    fail "Not running on macOS — NotchDeck requires macOS to build"
    problems=$((problems + 1))
fi

section "Xcode"
if xcode_path="$(xcode-select -p 2>/dev/null)"; then
    ok "Developer directory: $xcode_path"
else
    fail "xcode-select has no developer directory (install Xcode)"
    problems=$((problems + 1))
fi

if xcodebuild_version="$(xcodebuild -version 2>/dev/null)"; then
    ok "$(echo "$xcodebuild_version" | tr '\n' ' ')"
else
    fail "xcodebuild unavailable — install Xcode (not just Command Line Tools) and run: sudo xcode-select -s /Applications/Xcode.app"
    problems=$((problems + 1))
fi

if swift_version="$(swift --version 2>/dev/null | head -1)"; then
    ok "$swift_version"
else
    warn "swift not found on PATH"
fi

section "Project"
if [[ -d "$PROJECT" ]]; then
    ok "Found NotchDeck.xcodeproj"
    if schemes="$(xcodebuild -list -project "$PROJECT" 2>/dev/null | awk '/Schemes:/{f=1;next} f&&NF{print $1}')" && [[ -n "$schemes" ]]; then
        ok "Schemes: $(echo "$schemes" | tr '\n' ' ')"
    else
        warn "Could not list schemes (is Xcode installed and licensed?)"
    fi
else
    fail "NotchDeck.xcodeproj not found at $PROJECT"
    problems=$((problems + 1))
fi

section "Git"
if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    ok "Branch: $(git -C "$REPO_ROOT" branch --show-current)"

    remote="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
    if [[ -z "$remote" ]]; then
        warn "No 'origin' remote configured"
    elif [[ "$remote" =~ $EXPECTED_REMOTE_PATTERN ]]; then
        ok "origin: $remote"
    else
        warn "origin points to an unexpected URL: $remote"
    fi

    changes="$(git -C "$REPO_ROOT" status --porcelain | wc -l | tr -d ' ')"
    if [[ "$changes" == "0" ]]; then
        ok "Working tree clean"
    else
        warn "$changes uncommitted change(s) — run 'git status' for details"
    fi

    last_commit="$(git -C "$REPO_ROOT" log -1 --oneline 2>/dev/null || true)"
    [[ -n "$last_commit" ]] && ok "Latest commit: $last_commit"
else
    fail "Not a Git repository"
    problems=$((problems + 1))
fi

section "Summary"
if [[ "$problems" -eq 0 ]]; then
    ok "Environment looks ready. Next: open NotchDeck.xcodeproj (see DEVELOPMENT.md)"
else
    fail "$problems problem(s) found — see above"
fi

exit "$problems"
