#!/bin/bash

# Script to add new Swift files to Xcode project
# This will create simple stubs for missing handlers to conform to the new protocol

XCODE_PROJECT="/Users/karatsidhu/Developer/WardenApp/Warden.xcodeproj/project.pbxproj"

# New files to add
NEW_FILES=(
    "/Users/karatsidhu/Developer/WardenApp/Warden/Core/MCP/MCPServerConfig.swift"
    "/Users/karatsidhu/Developer/WardenApp/Warden/Core/MCP/MCPManager.swift"
    "/Users/karatsidhu/Developer/WardenApp/Warden/UI/Preferences/MCP/AddMCPAgentSheet.swift"
    "/Users/karatsidhu/Developer/WardenApp/Warden/UI/Preferences/MCP/MCPSettingsView.swift"
    "/Users/karatsidhu/Developer/WardenApp/Warden/UI/Chat/MCPAgentSelector.swift"
)

echo "New files to add to Xcode project:"
for file in "${NEW_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✓ $file"
    else
        echo "  ✗ $file (NOT FOUND)"
    fi
done

echo ""
echo "Please add these files to the Xcode project manually by:"
echo "1. Opening Warden.xcodeproj in Xcode"
echo "2. Right-clicking on the appropriate folder in the Project Navigator"
echo "3. Selecting 'Add Files to \"Warden\"...'"
echo "4. Navigating to the file location and adding it"
echo ""
echo "Alternatively, you can drag and drop the files into Xcode."
