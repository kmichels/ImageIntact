#!/bin/sh
# Auto-increment build number for Archive builds

# Only increment for Archive builds (both GitHub and App Store releases)
if [ "$ACTION" == "archive" ]; then
    echo "Auto-incrementing build number for archive..."
    
    # Get the current build number
    CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CURRENT_PROJECT_VERSION" "${PROJECT_FILE_PATH}/project.pbxproj" 2>/dev/null)
    
    if [ -z "$CURRENT_BUILD" ]; then
        CURRENT_BUILD=1
    fi
    
    # Increment build number
    NEW_BUILD=$((CURRENT_BUILD + 1))
    
    echo "Build number: $CURRENT_BUILD -> $NEW_BUILD"
    
    # Update project.pbxproj with new build number
    sed -i '' "s/CURRENT_PROJECT_VERSION = $CURRENT_BUILD;/CURRENT_PROJECT_VERSION = $NEW_BUILD;/g" "${PROJECT_FILE_PATH}/project.pbxproj"
    
    # Also update in Info.plist if it exists (for backwards compatibility)
    if [ -f "${BUILT_PRODUCTS_DIR}/${INFOPLIST_PATH}" ]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "${BUILT_PRODUCTS_DIR}/${INFOPLIST_PATH}"
    fi
else
    echo "Skipping build number increment (not an archive build)"
fi