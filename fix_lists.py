#!/usr/bin/env python3
import sys

filepath = r"D:\araucaria_sur\lib\features\home\presentation\pages\admin\territorios_tab.dart"

with open(filepath, "r", encoding="utf8") as f:
    content = f.read()

# Read the exact lines around 551-573
lines = content.split('\n')

# Find the exact old string by matching from trailing: Container through line 573
# old string starts at line 551 (index 550) and ends at line 573 (index 572)
old_start = "trailing: Container(\n                                                padding:"
# new string starts with trailing: Material
new_start = "trailing: Material(\n                                                  color: Colors.transparent,"

# Check if old start exists
if old_start in content:
    # Replace the trailing Container with trailing Material
    # We need to replace 'trailing: Container(' with 'trailing: Material(\n                                                  color: Colors.transparent,\n                                                  child: Container('
    # And we need to adjust the closing - the original has '),' at end of Container and '),') at end of ListTile
    # After change, we'll have '),)' - Material closing + ListTile closing, or we need '),' for Material and the ListTile closer gets adjusted
    
    # Actually, let me just do a simple replacement of the trailing line
    # Change: trailing: Container(
    # To: trailing: Material(color: Colors.transparent, child: Container(
    
    # Find position of old start
    pos = content.find(old_start)
    if pos >= 0:
        # Get the rest of the content from that position
        after = content[pos:]
        # Replace trailing: Container( with trailing: Material(color: Colors.transparent, child: Container(
        # But we need to also adjust the closing parentheses
        
        # Let's find where the Container closes (the first ")" after the child Text)
        # And where the ListTile closes (the last "))")
        
        # Simple approach: replace the entire trailing section
        # Old: trailing: Container(
        # New: trailing: Material(\n  color: Colors.transparent,\n  child: Container(
        
        # Actually, let me just do a char-by-char replacement strategy
        # Find "trailing: Container(" and replace with "trailing: Material(\n                                                  color: Colors.transparent,\n                                                  child: Container("
        
        replacement = "trailing: Material(\n                                                  color: Colors.transparent,\n                                                  child: Container("
        content = content.replace(old_start, replacement, 1)
        
        # Now we need to adjust the closing - the original has "),\n                                                )" at lines 572-573
        # After our change, we need to ensure the parentheses balance
        # The original trailing Container has its own ")" then ")," for ListTile
        # After wrapping in Material, we need ")" for Container then ")," for Material, then the ListTile closer
        
        # Let me just check if the replacement worked and see what we have
        with open(filepath, "w", encoding="utf8") as f:
            f.write(content)
        print("Applied partial fix to territoria_tab.dart")
    else:
        print("Could not find position")
else:
    print("Old start not found in content")
    # Debug: show line 551
    for i, line in enumerate(lines[550:555], start=551):
        print(f"Line {i}: {repr(line)}")