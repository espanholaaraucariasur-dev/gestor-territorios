with open(r"D:\araucaria_sur\lib\features\home\presentation\pages\publicador\publicador_tab.dart", "r", encoding="utf8") as f:
    content = f.read()

old = "import 'package:flutter/material.dart';"
new = "import 'package:flutter/material.dart';\nimport 'package:google_maps_flutter/google_maps_flutter.dart';"

if old in content:
    content = content.replace(old, new)
    with open(r"D:\araucaria_sur\lib\features\home\presentation\pages\publicador\publicador_tab.dart", "w", encoding="utf8") as f:
        f.write(content)
    print("Import added successfully")
else:
    print("Pattern not found - showing line 3")
    lines = content.split('\n')
    for i in range(2, 5):
        print(f"Line {i+1}: {repr(lines[i])}")