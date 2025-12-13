#!/bin/bash

# Generate EdDSA signature for Sparkle update
# Usage: ./scripts/generate_signature.sh v0.9

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 v0.9"
    exit 1
fi

VERSION="$1"
RELEASE_URL="https://github.com/SidhuK/WardenApp/releases/download/${VERSION}/Warden.zip"
PRIVATE_KEY=".keys/sparkle_private_key.pem"

echo "📥 Downloading release..."
TEMP_ZIP="/tmp/Warden-${VERSION}.zip"
curl -L --progress-bar -o "$TEMP_ZIP" "$RELEASE_URL" || exit 1

echo "🔐 Generating signature..."
if [ ! -f "$PRIVATE_KEY" ]; then
    echo "❌ Private key not found at $PRIVATE_KEY"
    echo ""
    echo "To create the key (one-time):"
    echo "  mkdir -p .keys"
    echo "  openssl genpkey -algorithm ed25519 -out .keys/sparkle_private_key.pem"
    echo "  chmod 600 .keys/sparkle_private_key.pem"
    exit 1
fi

SIGNATURE=$(openssl pkeyutl -sign -inkey "$PRIVATE_KEY" -in "$TEMP_ZIP" 2>/dev/null | openssl enc -base64 | tr -d '\n')

FILE_SIZE=$(stat -f%z "$TEMP_ZIP")

echo "✅ Signature generated!"
echo ""
echo "Update appcast.xml with:"
echo "  URL: $RELEASE_URL"
echo "  Length: $FILE_SIZE"
echo "  Signature: $SIGNATURE"
echo ""

rm "$TEMP_ZIP"
