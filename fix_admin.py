#!/usr/bin/env python3
filepath = r"D:\araucaria_sur\lib\features\home\presentation\pages\admin\admin_tab.dart"

with open(filepath, "r", encoding="utf8") as f:
    content = f.read()

# The old string - trailing Container from line 434 area
old = """trailing: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: predicado
                                        ? Colors.green.shade100
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    predicado ? 'Predicada' : 'Pendiente',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: predicado
                                          ? Colors.green.shade800
                                          : Colors.grey.shade700,
                                  ),
                                ),
                                ),"""

new = """trailing: Material(
                                                  color: Colors.transparent,
                                                  child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: predicado
                                        ? Colors.green.shade100
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    predicado ? 'Predicada' : 'Pendiente',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: predicado
                                          ? Colors.green.shade800
                                          : Colors.grey.shade700,
                                  ),
                                ),
                                ),
                                                ),"""

if old in content:
    content = content.replace(old, new)
    with open(filepath, "w", encoding="utf8") as f:
        f.write(content)
    print("Applied fix to admin_tab.dart")
else:
    print("Pattern not found in admin_tab.dart")
    # Show lines around 434
    lines = content.split('\n')
    for i in range(432, 455):
        print(f"{i+1}: {repr(lines[i])}")