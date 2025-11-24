#!/usr/bin/env python3
"""
Properly add MCP files to Xcode project with group structure
"""

import re
import uuid
import shutil

def generate_uuid():
    """Generate a 24-character hex ID similar to Xcode's format"""
    return uuid.uuid4().hex[:24].upper()

pbxproj_path = '/Users/karatsidhu/Developer/WardenApp/Warden.xcodeproj/project.pbxproj'

# Read the file
with open(pbxproj_path, 'r') as f:
    content = f.read()

# Create backup
backup_path = pbxproj_path + '.backup2'
shutil.copy2(pbxproj_path, backup_path)
print(f"💾 Created backup at: {backup_path}")

# Generate UUIDs for files and groups
core_group_uuid = generate_uuid()
core_mcp_group_uuid = generate_uuid()
ui_prefs_mcp_group_uuid = generate_uuid()

file_data = {
    'MCPServerConfig.swift': {
        'path': 'Core/MCP/MCPServerConfig.swift',
        'group_uuid': core_mcp_group_uuid,
        'file_ref_uuid': generate_uuid(),
        'build_file_uuid': generate_uuid()
    },
    'MCPManager.swift': {
        'path': 'Core/MCP/MCPManager.swift',
        'group_uuid': core_mcp_group_uuid,
        'file_ref_uuid': generate_uuid(),
        'build_file_uuid': generate_uuid()
    },
    'AddMCPAgentSheet.swift': {
        'path': 'UI/Preferences/MCP/AddMCPAgentSheet.swift',
        'group_uuid': ui_prefs_mcp_group_uuid,
        'file_ref_uuid': generate_uuid(),
        'build_file_uuid': generate_uuid()
    },
    'MCPSettingsView.swift': {
        'path': 'UI/Preferences/MCP/MCPSettingsView.swift',
        'group_uuid': ui_prefs_mcp_group_uuid,
        'file_ref_uuid': generate_uuid(),
        'build_file_uuid': generate_uuid()
    },
    'MCPAgentSelector.swift': {
        'path': 'UI/Chat/MCPAgentSelector.swift',
        'group_uuid': None,  # Will find Chat group UUID
        'file_ref_uuid': generate_uuid(),
        'build_file_uuid': generate_uuid()
    }
}

# Find the Chat group UUID
chat_group_match = re.search(r'([A-F0-9]{24}) /\* Chat \*/ = \{', content)
if chat_group_match:
    chat_group_uuid = chat_group_match.group(1)
    file_data['MCPAgentSelector.swift']['group_uuid'] = chat_group_uuid
    print(f"✓ Found Chat group: {chat_group_uuid}")
else:
    print("❌ Could not find Chat group UUID")
    exit(1)

# Find the Preferences group UUID
prefs_group_match = re.search(r'([A-F0-9]{24}) /\* Preferences \*/ = \{', content)
if not prefs_group_match:
    print("❌ Could not find Preferences group UUID")
    exit(1)
prefs_group_uuid = prefs_group_match.group(1)
print(f"✓ Found Preferences group: {prefs_group_uuid}")

# Find the main Warden group UUID
warden_group_match = re.search(r'([A-F0-9]{24}) /\* Warden \*/ = \{\n\s+isa = PBXGroup;', content)
if not warden_group_match:
    print("❌ Could not find Warden group UUID")
    exit(1)
warden_group_uuid = warden_group_match.group(1)
print(f"✓ Found Warden group: {warden_group_uuid}")

# 1. Add PBXBuildFile entries
build_file_section_start = content.find('/* Begin PBXBuildFile section */')
build_file_section_end = content.find('/* End PBXBuildFile section */', build_file_section_start)

build_file_entries = []
for filename, data in file_data.items():
    entry = f"\t\t{data['build_file_uuid']} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {data['file_ref_uuid']} /* {filename} */; }};\n"
    build_file_entries.append(entry)

content = content[:build_file_section_end] + ''.join(build_file_entries) + content[build_file_section_end:]
print("✓ Added PBXBuildFile entries")

# 2. Add PBXFileReference entries
file_ref_section_start = content.find('/* Begin PBXFileReference section */')
file_ref_section_end = content.find('/* End PBXFileReference section */', file_ref_section_start)

file_ref_entries = []
for filename, data in file_data.items():
    entry = f"\t\t{data['file_ref_uuid']} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = \"<group>\"; }};\n"
    file_ref_entries.append(entry)

content = content[:file_ref_section_end] + ''.join(file_ref_entries) + content[file_ref_section_end:]
print("✓ Added PBXFileReference entries")

# 3. Add to PBXSourcesBuildPhase
sources_build_phase_start = content.find('/* Begin PBXSourcesBuildPhase section */')
files_array_start = content.find('files = (', sources_build_phase_start)
files_array_end = content.find(');', files_array_start)

source_ref_entries = []
for filename, data in file_data.items():
    entry = f"\t\t\t\t{data['build_file_uuid']} /* {filename} in Sources */,\n"
    source_ref_entries.append(entry)

content = content[:files_array_end] + ''.join(source_ref_entries) + content[files_array_end:]
print("✓ Added to PBXSourcesBuildPhase")

# 4. Create Core group and add it to Warden group
group_section_start = content.find('/* Begin PBXGroup section */')
group_section_end = content.find('/* End PBXGroup section */', group_section_start)

# Core group
core_group = f"""\t\t{core_group_uuid} /* Core */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{core_mcp_group_uuid} /* MCP */,
\t\t\t);
\t\t\tpath = Core;
\t\t\tsourceTree = "<group>";
\t\t}};
"""

# Core/MCP group
core_mcp_group = f"""\t\t{core_mcp_group_uuid} /* MCP */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{file_data['MCPServerConfig.swift']['file_ref_uuid']} /* MCPServerConfig.swift */,
\t\t\t\t{file_data['MCPManager.swift']['file_ref_uuid']} /* MCPManager.swift */,
\t\t\t);
\t\t\tpath = MCP;
\t\t\tsourceTree = "<group>";
\t\t}};
"""

# UI/Preferences/MCP group
ui_prefs_mcp_group = f"""\t\t{ui_prefs_mcp_group_uuid} /* MCP */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{file_data['AddMCPAgentSheet.swift']['file_ref_uuid']} /* AddMCPAgentSheet.swift */,
\t\t\t\t{file_data['MCPSettingsView.swift']['file_ref_uuid']} /* MCPSettingsView.swift */,
\t\t\t);
\t\t\tpath = MCP;
\t\t\tsourceTree = "<group>";
\t\t}};
"""

# Add groups to the PBXGroup section
content = content[:group_section_end] + core_group + core_mcp_group + ui_prefs_mcp_group + content[group_section_end:]
print("✓ Created group structures")

# 5. Add Core group to Warden group children
warden_group_pattern = rf'({warden_group_uuid} /\* Warden \*/ = \{{\n\s+isa = PBXGroup;\n\s+children = \()'
warden_group_replacement = rf'\1\n\t\t\t\t{core_group_uuid} /* Core */,'
content = re.sub(warden_group_pattern, warden_group_replacement, content)
print("✓ Added Core to Warden group")

# 6. Add MCP group to Preferences group children  
prefs_group_pattern = rf'({prefs_group_uuid} /\* Preferences \*/ = \{{\n\s+isa = PBXGroup;\n\s+children = \()'
prefs_group_replacement = rf'\1\n\t\t\t\t{ui_prefs_mcp_group_uuid} /* MCP */,'
content = re.sub(prefs_group_pattern, prefs_group_replacement, content)
print("✓ Added MCP to Preferences group")

# 7. Add MCPAgentSelector to Chat group
chat_group_pattern = rf'({chat_group_uuid} /\* Chat \*/ = \{{\n\s+isa = PBXGroup;\n\s+children = \()'
chat_group_replacement = rf'\1\n\t\t\t\t{file_data["MCPAgentSelector.swift"]["file_ref_uuid"]} /* MCPAgentSelector.swift */,'
content = re.sub(chat_group_pattern, chat_group_replacement, content)
print("✓ Added MCPAgentSelector to Chat group")

# Write back
with open(pbxproj_path, 'w') as f:
    f.write(content)

print("\n🎉 Successfully added all files and groups to Xcode project!")
print("\nFiles added:")
for filename in file_data.keys():
    print(f"  ✓ {filename}")
