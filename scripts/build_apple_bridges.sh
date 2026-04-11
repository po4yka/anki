#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CONFIGURATION="${CONFIGURATION:-Debug}"
PLATFORM_NAME="${PLATFORM_NAME:-macosx}"
ARCHS_VALUE="${ARCHS:-$(uname -m)}"
PRIMARY_ARCH="${ARCHS_VALUE%% *}"
STAMP_ARCH="${NATIVE_ARCH_ACTUAL:-${PRIMARY_ARCH}}"

case "${CONFIGURATION}" in
  Debug|debug)
    CARGO_PROFILE="debug"
    BUILD_ARGS=()
    ;;
  Release|release)
    CARGO_PROFILE="release"
    BUILD_ARGS=(--release)
    ;;
  *)
    echo "error: unsupported CONFIGURATION '${CONFIGURATION}'. Expected Debug or Release." >&2
    exit 1
    ;;
esac

case "${PLATFORM_NAME}" in
  macosx)
    if [[ "${PRIMARY_ARCH}" == "x86_64" ]]; then
      RUST_TARGET="x86_64-apple-darwin"
    else
      RUST_TARGET="aarch64-apple-darwin"
    fi
    ;;
  iphoneos)
    RUST_TARGET="aarch64-apple-ios"
    ;;
  iphonesimulator)
    if [[ "${PRIMARY_ARCH}" == "x86_64" ]]; then
      RUST_TARGET="x86_64-apple-ios"
    else
      RUST_TARGET="aarch64-apple-ios-sim"
    fi
    ;;
  *)
    echo "error: unsupported PLATFORM_NAME '${PLATFORM_NAME}'." >&2
    exit 1
    ;;
esac

if ! rustup target list --installed | grep -qx "${RUST_TARGET}"; then
  echo "error: rust target '${RUST_TARGET}' is not installed." >&2
  echo "Install it with: rustup target add ${RUST_TARGET}" >&2
  exit 1
fi

cd "${REPO_ROOT}"

echo "Building Apple bridge staticlibs for ${RUST_TARGET} (${CARGO_PROFILE})"
cargo build --target "${RUST_TARGET}" -p anki_bridge -p atlas_bridge "${BUILD_ARGS[@]}"

for library in libanki_bridge.a libatlas_bridge.a; do
  artifact="${REPO_ROOT}/target/${RUST_TARGET}/${CARGO_PROFILE}/${library}"
  if [[ ! -f "${artifact}" ]]; then
    echo "error: expected bridge artifact '${artifact}' was not produced." >&2
    exit 1
  fi
done

STAMP_DIR="${REPO_ROOT}/target/.bridge-stamps"
mkdir -p "${STAMP_DIR}"
STAMP_FILE="${STAMP_DIR}/${PLATFORM_NAME}-${CONFIGURATION}-${STAMP_ARCH}"
touch "${STAMP_FILE}"

echo "Bridge artifacts ready in target/${RUST_TARGET}/${CARGO_PROFILE}"
