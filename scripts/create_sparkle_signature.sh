#!/bin/bash
# Helper script to generate Sparkle signatures for releases
# Usage: ./scripts/create_sparkle_signature.sh path/to/dmg path/to/private_key

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 <dmg_file> <private_key_path>"
    echo ""
    echo "Generates an EdDSA signature for a Sparkle update."
    echo ""
    echo "To generate a private key (one time):"
    echo "  openssl genpkey -algorithm ed25519 -out sparkle_private_key.pem"
    echo "  openssl pkey -in sparkle_private_key.pem -pubout -out sparkle_public_key.pem"
    echo ""
    echo "Add the public key to Info.plist as SUPublicEDKey"
    exit 1
fi

DMG_FILE="$1"
PRIVATE_KEY="$2"

if [ ! -f "$DMG_FILE" ]; then
    echo "Error: DMG file not found: $DMG_FILE"
    exit 1
fi

if [ ! -f "$PRIVATE_KEY" ]; then
    echo "Error: Private key not found: $PRIVATE_KEY"
    exit 1
fi

# Generate signature using openssl
SIGNATURE=$(openssl pkeyutl -sign -inkey "$PRIVATE_KEY" -in "$DMG_FILE" 2>/dev/null | openssl enc -base64 | tr -d '\n')

echo "Signature for $DMG_FILE:"
echo "$SIGNATURE"
echo ""
echo "File size: $(stat -f%z "$DMG_FILE") bytes"
