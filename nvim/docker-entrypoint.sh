#!/bin/sh
set -eu

home_dir="${HOME:-/tmp}"
mkdir -p "$home_dir"

git_user_name="${GIT_USER_NAME:-${DEFAULT_GIT_USER_NAME:-}}"
git_user_email="${GIT_USER_EMAIL:-${DEFAULT_GIT_USER_EMAIL:-}}"

# Prefer runtime env overrides, otherwise keep any user-provided git config.
if [ -n "$git_user_name" ] && { [ -n "${GIT_USER_NAME:-}" ] || ! git config --global --get user.name >/dev/null 2>&1; }; then
    git config --global user.name "$git_user_name"
fi

if [ -n "$git_user_email" ] && { [ -n "${GIT_USER_EMAIL:-}" ] || ! git config --global --get user.email >/dev/null 2>&1; }; then
    git config --global user.email "$git_user_email"
fi

exec nvim "$@"
