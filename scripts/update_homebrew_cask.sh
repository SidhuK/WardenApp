#!/bin/bash
# update_homebrew_cask.sh
# Automates updating the Homebrew Cask formula for new Warden releases
#
# Usage: ./scripts/update_homebrew_cask.sh <version>
# Example: ./scripts/update_homebrew_cask.sh 0.9.3

set -e

VERSION="${1}"
CASK_FILE="Casks/warden.rb"
DOWNLOAD_URL="https://github.com/SidhuK/WardenApp/releases/download/v${VERSION}/Warden.zip"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

if [ -z "$VERSION" ]; then
    echo -e "${RED}Error: Version argument required${NC}"
    echo "Usage: $0 <version>"
    echo "Example: $0 0.9.3"
    exit 1
fi

if [ ! -f "$CASK_FILE" ]; then
    echo -e "${RED}Error: Cask file not found at $CASK_FILE${NC}"
    echo "Run this script from the WardenApp root directory"
    exit 1
fi

echo -e "${YELLOW}📦 Updating Homebrew Cask for Warden v${VERSION}${NC}"
echo ""

# Check if release exists
echo "🔍 Checking if release v${VERSION} exists..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -L "$DOWNLOAD_URL")
if [ "$HTTP_STATUS" != "200" ]; then
    echo -e "${RED}Error: Release v${VERSION} not found on GitHub (HTTP $HTTP_STATUS)${NC}"
    echo "Make sure you've created the GitHub release first!"
    exit 1
fi
echo -e "${GREEN}✓ Release found${NC}"

# Calculate SHA256
echo "🔐 Calculating SHA256..."
SHA256=$(curl -sL "$DOWNLOAD_URL" | shasum -a 256 | cut -d' ' -f1)
echo -e "${GREEN}✓ SHA256: ${SHA256}${NC}"

# Update the cask file
echo "📝 Updating $CASK_FILE..."

# Update version
sed -i '' "s/version \"[^\"]*\"/version \"${VERSION}\"/" "$CASK_FILE"

# Update sha256
sed -i '' "s/sha256 \"[^\"]*\"/sha256 \"${SHA256}\"/" "$CASK_FILE"

echo -e "${GREEN}✓ Cask file updated${NC}"
echo ""

# Show the changes
echo -e "${YELLOW}📋 Updated values:${NC}"
grep -E "version|sha256" "$CASK_FILE" | head -2
echo ""

echo -e "${GREEN}✅ Done!${NC}"
echo ""
echo "Next steps:"
echo "  1. Review the changes: git diff Casks/warden.rb"
echo "  2. Commit: git add Casks/warden.rb && git commit -m 'Bump Homebrew cask to v${VERSION}'"
echo "  3. Copy Casks/warden.rb to your homebrew-warden repo"
echo "  4. Push both repos"
