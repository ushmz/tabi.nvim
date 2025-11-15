#!/usr/bin/env sh
set -Cue

if !(type luacheck &>/dev/null); then
    printf '\033[1;31m[ERROR]\033[0m command `luacheck` not found.\n' >&2
    exit 1
fi

luacheck . || {
    echo "\033[1;31m[ERROR]\033[0m Luacheck failed. Fix the issues before committing."
    exit 1
}
