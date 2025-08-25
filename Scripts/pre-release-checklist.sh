#!/bin/bash

# pre-release-checklist.sh
# Run this before creating a new release to ensure everything is ready

set -e

echo "📋 ImageIntact Pre-Release Checklist"
echo "====================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CHECKS_PASSED=0
CHECKS_FAILED=0

# Function to run a check
run_check() {
    local description="$1"
    local command="$2"
    
    echo -n "Checking: $description... "
    
    if eval "$command" > /dev/null 2>&1; then
        echo -e "${GREEN}✅${NC}"
        ((CHECKS_PASSED++))
        return 0
    else
        echo -e "${RED}❌${NC}"
        ((CHECKS_FAILED++))
        return 1
    fi
}

# 1. Check Git status
echo -e "${BLUE}1. Git Status${NC}"
run_check "Working directory clean" "git diff --quiet && git diff --cached --quiet"
run_check "On main branch" "[ $(git branch --show-current) = 'main' ]"
run_check "Up to date with origin" "git fetch && [ -z \"$(git log HEAD..origin/main --oneline)\" ]"
echo ""

# 2. Check version number
echo -e "${BLUE}2. Version Numbers${NC}"
PLIST_PATH="ImageIntact/Resources/Info.plist"
if [ -f "$PLIST_PATH" ]; then
    CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST_PATH" 2>/dev/null || echo "unknown")
    echo "Current version in Info.plist: $CURRENT_VERSION"
    
    # Check if version was bumped
    LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
    echo "Last Git tag: $LAST_TAG"
    
    if [ "v$CURRENT_VERSION" != "$LAST_TAG" ]; then
        echo -e "${GREEN}✅ Version has been bumped${NC}"
        ((CHECKS_PASSED++))
    else
        echo -e "${YELLOW}⚠️ Version number unchanged - make sure to bump it${NC}"
    fi
else
    echo -e "${RED}❌ Info.plist not found${NC}"
    ((CHECKS_FAILED++))
fi
echo ""

# 3. Build tests
echo -e "${BLUE}3. Build Tests${NC}"
run_check "Debug build succeeds" "xcodebuild -scheme ImageIntact -configuration Debug build -quiet"
run_check "Release build succeeds" "xcodebuild -scheme ImageIntact -configuration Release build -quiet"
echo ""

# 4. Update mechanism tests
echo -e "${BLUE}4. Update Mechanism${NC}"
if [ -f "./Scripts/validate-update-mechanism.sh" ]; then
    run_check "Update mechanism validation" "./Scripts/validate-update-mechanism.sh"
else
    echo -e "${YELLOW}⚠️ Update validation script not found${NC}"
fi
echo ""

# 5. Documentation
echo -e "${BLUE}5. Documentation${NC}"
run_check "README.md exists" "[ -f README.md ]"
run_check "CHANGELOG updated recently" "[ $(find . -name 'CHANGELOG*' -mtime -7 | wc -l) -gt 0 ]"
echo ""

# 6. Test mode cleanup
echo -e "${BLUE}6. Test Mode Cleanup${NC}"
echo -n "Checking: No test mode code in release... "
if ! grep -r "TEST MODE" --include="*.swift" . | grep -v "Scripts/" | grep -v "//" > /dev/null; then
    echo -e "${GREEN}✅${NC}"
    ((CHECKS_PASSED++))
else
    echo -e "${YELLOW}⚠️ Test mode references found (check if intentional)${NC}"
fi
echo ""

# Summary
echo "====================================="
echo -e "${BLUE}Summary:${NC}"
echo -e "  Checks passed: ${GREEN}$CHECKS_PASSED${NC}"
if [ $CHECKS_FAILED -gt 0 ]; then
    echo -e "  Checks failed: ${RED}$CHECKS_FAILED${NC}"
else
    echo -e "  Checks failed: $CHECKS_FAILED"
fi
echo ""

if [ $CHECKS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ All checks passed! Ready to create release.${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Archive the app in Xcode (Product → Archive)"
    echo "  2. Export as Developer ID signed app"
    echo "  3. Create DMG with create-dmg script"
    echo "  4. Create GitHub release with DMG attached"
    echo "  5. Tag the release (git tag v$CURRENT_VERSION && git push --tags)"
    exit 0
else
    echo -e "${RED}❌ Some checks failed. Please fix issues before releasing.${NC}"
    exit 1
fi