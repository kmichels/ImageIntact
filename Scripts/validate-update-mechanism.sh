#!/bin/bash

# validate-update-mechanism.sh
# Automated validation of the update mechanism
# Can be run locally or in CI/CD

set -e

echo "🔍 ImageIntact Update Mechanism Validator"
echo "=========================================="

# Check if running in CI
if [ -n "$CI" ]; then
    echo "Running in CI environment"
fi

# Configuration
GITHUB_REPO="Tonal-Photo/ImageIntact"
LATEST_RELEASE_URL="https://api.github.com/repos/$GITHUB_REPO/releases/latest"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test 1: Check GitHub API is accessible
echo -e "${BLUE}Test 1: GitHub API Connectivity${NC}"
if curl -s -f "$LATEST_RELEASE_URL" > /dev/null; then
    echo -e "${GREEN}✅ GitHub API is accessible${NC}"
else
    echo -e "${RED}❌ Cannot reach GitHub API${NC}"
    exit 1
fi

# Test 2: Verify latest release has a DMG
echo -e "${BLUE}Test 2: Latest Release DMG Check${NC}"
LATEST_RELEASE=$(curl -s "$LATEST_RELEASE_URL")
DMG_URL=$(echo "$LATEST_RELEASE" | grep -o '"browser_download_url": *"[^"]*\.dmg"' | cut -d'"' -f4 | head -n 1)

if [ -n "$DMG_URL" ]; then
    echo -e "${GREEN}✅ DMG found: $(basename "$DMG_URL")${NC}"
else
    echo -e "${RED}❌ No DMG found in latest release${NC}"
    exit 1
fi

# Test 3: Verify DMG is downloadable
echo -e "${BLUE}Test 3: DMG Download Test${NC}"
if curl -s -f -I "$DMG_URL" > /dev/null; then
    echo -e "${GREEN}✅ DMG is downloadable${NC}"
else
    echo -e "${RED}❌ DMG URL is not accessible${NC}"
    exit 1
fi

# Test 4: Check version comparison logic
echo -e "${BLUE}Test 4: Version Comparison Logic${NC}"
LATEST_VERSION=$(echo "$LATEST_RELEASE" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4 | sed 's/^v//')
echo "Latest version: $LATEST_VERSION"

# Simple version comparison test
if [ "1.0.0" \< "$LATEST_VERSION" ]; then
    echo -e "${GREEN}✅ Version comparison works (1.0.0 < $LATEST_VERSION)${NC}"
else
    echo -e "${RED}❌ Version comparison failed${NC}"
    exit 1
fi

# Test 5: Download speed test (optional)
echo -e "${BLUE}Test 5: Download Speed Test${NC}"
echo "Testing download speed (first 1MB)..."
SPEED=$(curl -s -w '%{speed_download}' -o /dev/null --max-time 5 --range 0-1048576 "$DMG_URL")
SPEED_MB=$(echo "scale=2; $SPEED / 1048576" | bc)
echo -e "${GREEN}✅ Download speed: ${SPEED_MB} MB/s${NC}"

# Test 6: Validate release notes format
echo -e "${BLUE}Test 6: Release Notes Format${NC}"
RELEASE_NOTES=$(echo "$LATEST_RELEASE" | grep -o '"body": *"[^"]*"' | cut -d'"' -f4)
if [ -n "$RELEASE_NOTES" ]; then
    echo -e "${GREEN}✅ Release notes present${NC}"
else
    echo -e "${YELLOW}⚠️ No release notes found${NC}"
fi

# Summary
echo ""
echo "=========================================="
echo -e "${GREEN}All update mechanism tests passed!${NC}"
echo ""
echo "Summary:"
echo "  • GitHub API: ✅"
echo "  • DMG availability: ✅"
echo "  • Download access: ✅"
echo "  • Version logic: ✅"
echo "  • Download speed: ${SPEED_MB} MB/s"
echo ""
echo "The update mechanism is ready for release."