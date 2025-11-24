#!/usr/bin/env python3
"""
Fix file path references in Xcode project
"""

import re

pbxproj_path = '/Users/karatsidhu/Developer/WardenApp/Warden.xcodeproj/project.pbxproj'

# Read the file
with open(pbxproj_path, 'r') as f:
    content = f.read()

# Define the files and their correct paths
file_fixes = {
    'MCPServerConfig.swift': 'Core/MCP/MCPServerConfig.swift',
    'MCPManager.swift': 'Core/MCP/MCPManager.swift',
    'AddMCPAgentSheet.swift': 'UI/Preferences/MCP/AddMCPAgentSheet.swift',
    'MCPSettingsView.swift': 'UI/Preferences/MCP/MCPSettingsView.swift',
    'MCPAgentSelector.swift': 'UI/Chat/MCPAgentSelector.swift',
}

# Update the file references
for filename, correct_path in file_fixes.items():
    # Pattern to find the file reference line
    pattern = rf'(\/\* {re.escape(filename)} \*/ = {{isa = PBXFileReference;[^;]+path = ){re.escape(filename)}'
    replacement = rf'\1{correct_path}'
    content = re.sub(pattern, replacement, content)

# Write back
with open(pbxproj_path, 'w') as f:
    f.write(content)

print("✅ Fixed file path references in Xcode project")
print("\nUpdated paths:")
for filename, correct_path in file_fixes.items():
    print(f"  {filename} -> {correct_path}")
