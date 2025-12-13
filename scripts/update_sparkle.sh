#!/bin/bash

# Update Sparkle appcast.xml with new release
# Note: You can manually get file size from GitHub release page

set -e

RELEASE_URL="https://github.com/SidhuK/WardenApp/releases/download/v0.9/Warden.zip"
VERSION="0.9"
APPCAST_FILE="appcast.xml"

# For v0.9, enter estimated file size (get from GitHub release page)
# This is a placeholder - update with actual file size from GitHub
FILE_SIZE="${1:-13500000}"

if [ -z "$1" ]; then
    echo "⚠️  Using estimated file size: $FILE_SIZE bytes"
    echo "📝 Run with: ./scripts/update_sparkle.sh <file_size>"
    echo "   (Get file size from GitHub release page)"
fi

# Generate signature using sparkle_private_key
echo "🔐 Generating Sparkle EdDSA signature..."
PRIVATE_KEY=".keys/sparkle_private_key.pem"

if [ ! -f "$PRIVATE_KEY" ]; then
    echo "❌ Error: Private key not found at $PRIVATE_KEY"
    exit 1
fi

# Create temp file with release data for signing
TEMP_ZIP="/tmp/Warden-0.9.zip"
if [ ! -f "$TEMP_ZIP" ]; then
    echo "📥 Downloading release zip for signature..."
    curl -L --progress-bar -o "$TEMP_ZIP" "$RELEASE_URL" || {
        echo "⚠️  Could not download. Using placeholder signature."
        SIGNATURE="PLACEHOLDER_SIGNATURE_FROM_RELEASE_NOTES"
    }
fi

if [ -f "$TEMP_ZIP" ]; then
    SIGNATURE=$(openssl dgst -sha256 -sign "$PRIVATE_KEY" "$TEMP_ZIP" | openssl base64 | tr -d '\n')
    FILE_SIZE=$(stat -f%z "$TEMP_ZIP")
    echo "✅ Signature generated"
    rm "$TEMP_ZIP"
fi

# Get current date in RFC 2822 format
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")

# Create new item entry
NEW_ITEM="        <item>
            <title>Version $VERSION</title>
            <description><![CDATA[
                <ul>
                <li>Faster, smoother streaming replies</li>
                <li>Better performance in large chats</li>
                <li>Cleaner markdown handling</li>
                <li>Improved stability and cancellation behavior</li>
                <li>Smarter buffering for UI responsiveness</li>
                <li>More resilient streaming parsing</li>
                <li>Safer attachment handling</li>
                <li>Better logging and diagnostics</li>
                <li>Virtual message list for large conversations</li>
                </ul>
            ]]></description>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$VERSION</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <enclosure url=\"$RELEASE_URL\"
                       sparkle:version=\"$VERSION\"
                       sparkle:shortVersionString=\"$VERSION\"
                       type=\"application/zip\"
                       length=\"$FILE_SIZE\"
                       sparkle:edSignature=\"$SIGNATURE\" />
        </item>
        "

# Update appcast.xml - insert new item before existing items
echo "✏️  Updating $APPCAST_FILE..."

# Create temporary file
TEMP_APPCAST="/tmp/appcast_temp.xml"

# Copy header (lines 1-8) and insert new item
head -n 8 "$APPCAST_FILE" > "$TEMP_APPCAST"
echo "" >> "$TEMP_APPCAST"
echo "$NEW_ITEM" >> "$TEMP_APPCAST"
tail -n +9 "$APPCAST_FILE" >> "$TEMP_APPCAST"

# Replace original
mv "$TEMP_APPCAST" "$APPCAST_FILE"

echo "✅ Sparkle update complete!"
echo "📝 Updated appcast.xml with version $VERSION"
echo "📅 Published: $PUB_DATE"
echo "📦 File size: $FILE_SIZE bytes"
echo "🔐 EdDSA Signature: $SIGNATURE"
echo ""
echo "Next steps:"
echo "1. Verify signature from GitHub release notes if placeholder was used"
echo "2. Commit appcast.xml changes"
echo "3. Push to main branch"
echo "4. Users will be notified automatically"
