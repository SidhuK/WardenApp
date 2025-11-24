#!/usr/bin/env python3
"""
Remove override keywords from API handler methods that conflict with base class default implementations
"""

import re
import os

handlers = [
    '/Users/karatsidhu/Developer/WardenApp/Warden/Utilities/APIHandlers/DeepseekHandler.swift',
    '/Users/karatsidhu/Developer/WardenApp/Warden/Utilities/APIHandlers/MistralHandler.swift',
    '/Users/karatsidhu/Developer/WardenApp/Warden/Utilities/APIHandlers/LMStudioHandler.swift',
    '/Users/karatsidhu/Developer/WardenApp/Warden/Utilities/APIHandlers/OpenRouterHandler.swift',
    '/Users/karatsidhu/Developer/WardenApp/Warden/Utilities/APIHandlers/ClaudeHandler.swift',
    '/Users/karatsidhu/Developer/WardenApp/Warden/Utilities/APIHandlers/PerplexityHandler.swift',
    '/Users/karatsidhu/Developer/WardenApp/Warden/Utilities/APIHandlers/OllamaHandler.swift'
]

methods_to_fix = [
    'prepareRequest',
    'parseJSONResponse',
    'parseDeltaJSONResponse',
    'sendMessageStream'
]

for handler_path in handlers:
    if not os.path.exists(handler_path):
        print(f"⚠️  File not found: {handler_path}")
        continue
    
    with open(handler_path, 'r') as f:
        content = f.read()
    
    # Remove override keyword from specific methods
    for method in methods_to_fix:
        # Pattern to match override func methodName
        pattern = rf'(\s+)override\s+(func\s+{re.escape(method)}\b)'
        replacement = r'\1\2'
        content = re.sub(pattern, replacement, content)
    
    with open(handler_path, 'w') as f:
        f.write(content)
    
    filename = os.path.basename(handler_path)
    print(f"✓ Fixed {filename}")

print("\n✅ All handlers updated")
