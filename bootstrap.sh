#!/usr/bin/env bash
# rice bootstrap — clone the repo and run the installer.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/triscacezar-droid/rice/main/bootstrap.sh | bash
#
# Env overrides:
#   RICE_HOME   where to clone        (default: $HOME/rice)
#   REPO_URL    repo URL              (default: https://github.com/triscacezar-droid/rice.git)
set -euo pipefail

RICE_HOME="${RICE_HOME:-$HOME/rice}"
REPO_URL="${REPO_URL:-https://github.com/triscacezar-droid/rice.git}"

cyan() { printf "\033[1;36m==> %s\033[0m\n" "$*"; }
red()  { printf "\033[1;31m!!  %s\033[0m\n" "$*" >&2; }

command -v git >/dev/null || { red "git not installed — sudo apt install git"; exit 1; }

if [[ -d "$RICE_HOME/.git" ]]; then
    cyan "Updating existing clone at $RICE_HOME"
    git -C "$RICE_HOME" pull --ff-only
else
    cyan "Cloning $REPO_URL into $RICE_HOME"
    git clone "$REPO_URL" "$RICE_HOME"
fi

cyan "Running installer"
exec "$RICE_HOME/install.sh"
