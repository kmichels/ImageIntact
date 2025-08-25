#!/bin/bash

# test-update-flow.sh
# Tests the update download flow before releasing a new version

set -e

echo "🧪 ImageIntact Update Flow Test"
echo "================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROJECT_DIR="$(dirname "$0")/.."
SCHEME="ImageIntact (Test Updates)"
CONFIGURATION="Debug"

echo -e "${YELLOW}Step 1: Building app with test scheme...${NC}"
cd "$PROJECT_DIR"

# Build the app with test mode
xcodebuild -scheme "$SCHEME" \
           -configuration "$CONFIGURATION" \
           -derivedDataPath ./DerivedData \
           build 2>&1 | grep -E "(Succeeded|Failed|Error)" || true

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo -e "${RED}❌ Build failed${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Build successful${NC}"

# Find the built app
APP_PATH=$(find ./DerivedData -name "ImageIntact.app" -type d | head -n 1)

if [ -z "$APP_PATH" ]; then
    echo -e "${RED}❌ Could not find built app${NC}"
    exit 1
fi

echo -e "${YELLOW}Step 2: Launching app in test mode...${NC}"
echo "App path: $APP_PATH"

# Launch the app with test arguments
open "$APP_PATH" --args --test-update --mock-version 1.0.0 &
APP_PID=$!

echo -e "${YELLOW}Step 3: Waiting for update check...${NC}"
echo "The app should now:"
echo "  1. Show TEST MODE banner"
echo "  2. Check for updates automatically"
echo "  3. Find version 1.2.6 available"
echo "  4. Show the update dialog"
echo ""
echo "Please verify the update flow works correctly."
echo "When done testing, press Enter to continue..."
read -r

# Clean up
echo -e "${YELLOW}Step 4: Cleaning up...${NC}"
rm -rf ./DerivedData

echo -e "${GREEN}✅ Update flow test complete${NC}"
echo ""
echo "If the test was successful, you can now:"
echo "  1. Archive the release build"
echo "  2. Create the DMG"
echo "  3. Upload to GitHub releases"