#!/usr/bin/env bash
# Extrait un conffile depuis le .deb installe (Debian).
# Usage: restore-conffile-from-package.sh <chemin-absolu> <extract-root>
set -euo pipefail

FILE="${1:?chemin absolu requis}"
EXTRACT_ROOT="${2:?repertoire d extraction requis}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_ok() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_err() { echo -e "${RED}[ERR]${NC} $*" >&2; }

mkdir -p "$EXTRACT_ROOT"

if ! command -v dpkg >/dev/null 2>&1 || ! command -v dpkg-deb >/dev/null 2>&1; then
  log_err "dpkg/dpkg-deb requis (Debian only)"
  exit 1
fi

pkg="$(dpkg -S "$FILE" 2>/dev/null | awk -F': ' '{print $1}' | head -1 || true)"
if [[ -z "$pkg" ]]; then
  if dpkg -s nginx >/dev/null 2>&1; then
    pkg="nginx"
  else
    log_err "Aucun paquet proprietaire pour $FILE"
    exit 1
  fi
  log_warn "$FILE non indexe par dpkg, fallback paquet $pkg"
fi

work="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf '$work'" EXIT

ver="$(dpkg-query -W -f='${Version}' "$pkg")"
# Prefere le .deb deja present en cache apt.
cached="$(ls -1t /var/cache/apt/archives/${pkg}_*.deb 2>/dev/null | head -1 || true)"

if [[ -n "$cached" ]]; then
  deb="$cached"
else
  (cd "$work" && apt-get download "${pkg}=${ver}" >/dev/null)
  deb="$(ls -1 "$work"/*.deb)"
fi

dpkg-deb -x "$deb" "$work/root"
src="$work/root${FILE}"
if [[ ! -f "$src" ]]; then
  log_err "$FILE absent du paquet $pkg"
  exit 1
fi

mkdir -p "$(dirname "${EXTRACT_ROOT}${FILE}")"
cp -a "$src" "${EXTRACT_ROOT}${FILE}"
log_ok "Extrait $FILE depuis $pkg=$ver"
