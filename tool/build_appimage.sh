#!/usr/bin/env bash
# Build a deterministic x86_64 AppImage from Flutter's Linux release bundle.
set -euo pipefail

readonly PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly BUILD_ROOT="${PROJECT_ROOT}/build/appimage"
readonly BUNDLE="${1:-${PROJECT_ROOT}/build/linux/x64/release/bundle}"
readonly APPDIR="${BUILD_ROOT}/AppDir"
readonly OUTPUT="${2:-${BUILD_ROOT}/prompt-x86_64.AppImage}"
readonly TOOL="${BUILD_ROOT}/appimagetool-x86_64.AppImage"
readonly TOOL_URL="https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage"
# Digest published by the official AppImage/appimagetool 1.9.1 release API:
# https://api.github.com/repos/AppImage/appimagetool/releases/263382884/assets/324406736
readonly TOOL_SHA256="ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0"

readonly HOST_ARCH="$(uname -m)"
TOOL_COMMAND=("${TOOL}")
if [[ "${HOST_ARCH}" != "x86_64" ]]; then
  qemu_x86_64=""
  for candidate in qemu-x86_64 qemu-x86_64-static; do
    if command -v "${candidate}" >/dev/null 2>&1; then
      qemu_x86_64="$(command -v "${candidate}")"
      break
    fi
  done
  if [[ -z "${qemu_x86_64}" ]]; then
    printf 'x86_64 AppImage build requires qemu-x86_64 (or qemu-x86_64-static) on %s; FUSE and binfmt are not used\n' "${HOST_ARCH}" >&2
    exit 1
  fi
  TOOL_COMMAND=("${qemu_x86_64}" "${TOOL}" --appimage-extract-and-run)
fi

if [[ ! -d "${BUNDLE}" || ! -x "${BUNDLE}/prompt" ]]; then
  printf 'Flutter Linux bundle with executable prompt not found: %s\n' "${BUNDLE}" >&2
  exit 1
fi

mkdir -p "${BUILD_ROOT}"
if [[ ! -f "${TOOL}" ]]; then
  command -v curl >/dev/null || { printf 'curl is required\n' >&2; exit 1; }
  curl --fail --location --silent --show-error --retry 3 --output "${TOOL}" "${TOOL_URL}"
fi
actual_sha256="$(sha256sum "${TOOL}" | cut -d ' ' -f 1)"
if [[ "${actual_sha256}" != "${TOOL_SHA256}" ]]; then
  printf 'appimagetool checksum mismatch: expected %s, got %s\n' "${TOOL_SHA256}" "${actual_sha256}" >&2
  exit 1
fi
chmod 0755 "${TOOL}"

rm -rf "${APPDIR}"
mkdir -p "${APPDIR}"
cp -a "${BUNDLE}/." "${APPDIR}/"
install -m 0755 "${PROJECT_ROOT}/linux/packaging/AppRun" "${APPDIR}/AppRun"
install -m 0644 "${PROJECT_ROOT}/linux/packaging/prompt.desktop" "${APPDIR}/prompt.desktop"
install -Dm 0644 "${PROJECT_ROOT}/web/icons/Icon-512.png" "${APPDIR}/prompt.png"

mkdir -p "$(dirname -- "${OUTPUT}")"
export ARCH=x86_64
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}"
find "${APPDIR}" -exec touch -h -d "@${SOURCE_DATE_EPOCH}" {} +
rm -f "${OUTPUT}"
"${TOOL_COMMAND[@]}" "${APPDIR}" "${OUTPUT}"
printf 'Wrote %s\n' "${OUTPUT}"
