#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$INSTALL_DIR/engine.sh"

backend_install_main() {
  main "$@"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  backend_install_main "$@"
fi
