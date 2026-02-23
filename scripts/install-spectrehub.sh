#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-latest}"
REPO="ppiankov/spectrehub"

# Resolve "latest" to actual tag
if [ "$VERSION" = "latest" ]; then
  VERSION=$(gh release list -R "$REPO" --limit 1 --json tagName --jq '.[0].tagName')
  echo "Resolved latest → $VERSION"
fi

OS="linux"
ARCH="amd64"

case "$(uname -m)" in
  aarch64|arm64) ARCH="arm64" ;;
  x86_64)        ARCH="amd64" ;;
esac

BINARY="spectrehub-${OS}-${ARCH}"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${VERSION}/${BINARY}"

echo "Installing SpectreHub ${VERSION} (${OS}/${ARCH})..."
curl -fsSL "$DOWNLOAD_URL" -o /usr/local/bin/spectrehub
chmod +x /usr/local/bin/spectrehub

spectrehub version
echo "SpectreHub installed."
