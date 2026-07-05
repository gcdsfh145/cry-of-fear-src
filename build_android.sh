#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if ! command -v pwsh &> /dev/null; then
    echo "Error: PowerShell Core (pwsh) is required but not installed."
    echo "Please install it: https://learn.microsoft.com/powershell/scripting/install/installing-powershell"
    exit 1
fi

pwsh -NoProfile -ExecutionPolicy Bypass -File "$DIR/scripts/build-android.ps1" "$@"
