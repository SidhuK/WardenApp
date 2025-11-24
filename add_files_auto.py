#!/usr/bin/env python3
"""
Script to add files to Xcode project.pbxproj (Auto-run version)
This modifies the project file directly to add new source files.
"""

import os
import uuid
import shutil

def generate_uuid():
    """Generate a 24-character hex ID similar to Xcode's format"""
    return uuid.uuid4().hex[:24].upper()

def add_files_to_pbxproj(pbxproj_path, files_to_add):
    """Add files to the Xcode project"""
    
    with open(pbxproj_path, 'r') as f:
        content = f.read()
    
    # Generate UUIDs for each file (we need 2 per file: one for PBXFileReference, one for PBXBuildFile)
    file_entries = []
    for filepath in files_to_add:
        filename = os.path.basename(filepath)
        file_ref_uuid = generate_uuid()
        build_file_uuid = generate_uuid()
        
        file_entries.append({
            'filepath': filepath,
            'filename': filename,
            'file_ref_uuid': file_ref_uuid,
            'build_file_uuid': build_file_uuid
        })
    
    # Find the PBXBuildFile section and add entries
    build_file_section_start = content.find('/* Begin PBXBuildFile section */')
    if build_file_section_start == -1:
        print("Error: Could not find PBXBuildFile section")
        return False
    
    build_file_section_end = content.find('/* End PBXBuildFile section */', build_file_section_start)
    
    build_file_entries = []
    for entry in file_entries:
        build_file_entry = f"\t\t{entry['build_file_uuid']} /* {entry['filename']} in Sources */ = {{isa = PBXBuildFile; fileRef = {entry['file_ref_uuid']} /* {entry['filename']} */; }};\n"
        build_file_entries.append(build_file_entry)
    
    # Insert before the end marker
    content = content[:build_file_section_end] + ''.join(build_file_entries) + content[build_file_section_end:]
    
    # Find PBXFileReference section and add entries
    file_ref_section_start = content.find('/* Begin PBXFileReference section */')
    if file_ref_section_start == -1:
        print("Error: Could not find PBXFileReference section")
        return False
    
    file_ref_section_end = content.find('/* End PBXFileReference section */', file_ref_section_start)
    
    file_ref_entries = []
    for entry in file_entries:
        file_ref_entry = f"\t\t{entry['file_ref_uuid']} /* {entry['filename']} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {entry['filename']}; sourceTree = \"<group>\"; }};\n"
        file_ref_entries.append(file_ref_entry)
    
    content = content[:file_ref_section_end] + ''.join(file_ref_entries) + content[file_ref_section_end:]
    
    # Find PBXSourcesBuildPhase and add build file references
    sources_build_phase_start = content.find('/* Begin PBXSourcesBuildPhase section */')
    if sources_build_phase_start == -1:
        print("Error: Could not find PBXSourcesBuildPhase section")
        return False
    
    # Find the files = ( array in the sources build phase
    files_array_start = content.find('files = (', sources_build_phase_start)
    if files_array_start == -1:
        print("Error: Could not find files array in PBXSourcesBuildPhase")
        return False
    
    files_array_end = content.find(');', files_array_start)
    
    source_ref_entries = []
    for entry in file_entries:
        source_ref_entry = f"\t\t\t\t{entry['build_file_uuid']} /* {entry['filename']} in Sources */,\n"
        source_ref_entries.append(source_ref_entry)
    
    content = content[:files_array_end] + ''.join(source_ref_entries) + content[files_array_end:]
    
    # Write back
    with open(pbxproj_path, 'w') as f:
        f.write(content)
    
    print(f"✅ Successfully added {len(file_entries)} files to the Xcode project")
    return True

if __name__ == '__main__':
    pbxproj_path = '/Users/karatsidhu/Developer/WardenApp/Warden.xcodeproj/project.pbxproj'
    
    files_to_add = [
        '/Users/karatsidhu/Developer/WardenApp/Warden/Core/MCP/MCPServerConfig.swift',
        '/Users/karatsidhu/Developer/WardenApp/Warden/Core/MCP/MCPManager.swift',
        '/Users/karatsidhu/Developer/WardenApp/Warden/UI/Preferences/MCP/AddMCPAgentSheet.swift',
        '/Users/karatsidhu/Developer/WardenApp/Warden/UI/Preferences/MCP/MCPSettingsView.swift',
        '/Users/karatsidhu/Developer/WardenApp/Warden/UI/Chat/MCPAgentSelector.swift',
    ]
    
    # Check if files exist
    missing_files = []
    for filepath in files_to_add:
        if not os.path.exists(filepath):
            missing_files.append(filepath)
    
    if missing_files:
        print("❌ Error: The following files do not exist:")
        for f in missing_files:
            print(f"  - {f}")
        exit(1)
    
    print("📦 Files to add:")
    for f in files_to_add:
        print(f"  ✓ {os.path.basename(f)}")
    print()
    
    # Backup the project file first
    backup_path = pbxproj_path + '.backup'
    shutil.copy2(pbxproj_path, backup_path)
    print(f"💾 Created backup at: {backup_path}")
    print()
    
    if add_files_to_pbxproj(pbxproj_path, files_to_add):
        print("\n🎉 Files added successfully!")
        print("You can now open the project in Xcode.")
    else:
        print("\n❌ Failed to add files. Restoring backup...")
        shutil.copy2(backup_path, pbxproj_path)
        print(f"Backup restored from: {backup_path}")
        exit(1)
