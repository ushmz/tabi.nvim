#!/bin/sh
set -Cue

if !(type stylua &>/dev/null); then
    printf '\033[1;31m[ERROR]\033[0m command `stylua` not found.\n' >&2
    exit 1
fi

stylua --check . || {
    echo "\033[1;31m[ERROR]\033[0m Stylua check failed. Run 'stylua .' to fix formatting."
    exit 1
}
