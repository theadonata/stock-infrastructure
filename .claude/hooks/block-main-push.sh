#!/usr/bin/env bash
# PreToolUse hook (Bash matcher): blocks `git push` that targets main/master.
stdin_json=$(cat)
cmd=$(echo "$stdin_json" | grep -oP '"command"\s*:\s*"\K(?:\\.|[^"\\])*' | head -n1)
cmd=$(printf '%b' "${cmd//\\\"/\"}")
[ -z "$cmd" ] && exit 0

echo "$cmd" | grep -Eiq '(^|[;&|]|[[:space:]])git[[:space:]]+push([[:space:]]|$)' || exit 0

target_branch=""
echo "$cmd" | grep -Eq '(^|[^A-Za-z0-9_/.-])main([^A-Za-z0-9_/.-]|$)' && target_branch="main"
echo "$cmd" | grep -Eq '(^|[^A-Za-z0-9_/.-])master([^A-Za-z0-9_/.-]|$)' && target_branch="master"

current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

blocked=false
if [ -n "$target_branch" ]; then
  blocked=true
elif [ "$current_branch" = "main" ] || [ "$current_branch" = "master" ]; then
  blocked=true
fi

if [ "$blocked" = true ]; then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Direct push to main/master is blocked by policy. Push a feature branch and open a pull request instead."}}'
fi
exit 0
