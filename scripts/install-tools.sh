#!/usr/bin/env bash
set -euo pipefail

TOOLS_INPUT="${1:-auto}"

# All supported spectre tools
ALL_TOOLS=(vaultspectre s3spectre kafkaspectre clickspectre pgspectre mongospectre)

# Parse tool list
if [ "$TOOLS_INPUT" = "auto" ]; then
  TOOLS=("${ALL_TOOLS[@]}")
else
  IFS=',' read -ra TOOLS <<< "$TOOLS_INPUT"
  # Trim whitespace
  for i in "${!TOOLS[@]}"; do
    TOOLS[$i]=$(echo "${TOOLS[$i]}" | xargs)
  done
fi

OS="linux"
ARCH="amd64"

case "$(uname -m)" in
  aarch64|arm64) ARCH="arm64" ;;
  x86_64)        ARCH="amd64" ;;
esac

INSTALLED=0
FAILED=0

for TOOL in "${TOOLS[@]}"; do
  REPO="ppiankov/${TOOL}"

  # Get latest version
  VERSION=$(gh release list -R "$REPO" --limit 1 --json tagName --jq '.[0].tagName' 2>/dev/null || echo "")
  if [ -z "$VERSION" ]; then
    echo "⚠ ${TOOL}: no releases found, skipping"
    FAILED=$((FAILED + 1))
    continue
  fi

  # Strip v prefix for asset name
  VERSION_NUM="${VERSION#v}"
  ASSET="${TOOL}_${VERSION_NUM}_${OS}_${ARCH}.tar.gz"
  DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${VERSION}/${ASSET}"

  echo "Installing ${TOOL} ${VERSION}..."

  TMPDIR=$(mktemp -d)
  if curl -fsSL "$DOWNLOAD_URL" -o "${TMPDIR}/${ASSET}" 2>/dev/null; then
    tar -xzf "${TMPDIR}/${ASSET}" -C "${TMPDIR}"
    # Find the binary — could be at root or in a subdirectory
    BINARY=$(find "${TMPDIR}" -name "${TOOL}" -type f | head -1)
    if [ -n "$BINARY" ]; then
      cp "$BINARY" "/usr/local/bin/${TOOL}"
      chmod +x "/usr/local/bin/${TOOL}"
      echo "✓ ${TOOL} ${VERSION} installed"
      INSTALLED=$((INSTALLED + 1))
    else
      echo "⚠ ${TOOL}: binary not found in archive, skipping"
      FAILED=$((FAILED + 1))
    fi
  else
    echo "⚠ ${TOOL}: download failed (${ASSET}), skipping"
    FAILED=$((FAILED + 1))
  fi

  rm -rf "$TMPDIR"
done

echo ""
echo "Installed: ${INSTALLED} tools, Failed: ${FAILED}"

if [ "$INSTALLED" -eq 0 ]; then
  echo "::error::No spectre tools could be installed"
  exit 1
fi
