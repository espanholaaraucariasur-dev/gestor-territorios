with open(r"D:\araucaria_sur\lib\features\home\presentation\pages\admin\territorios_tab.dart", "r", encoding="utf8") as f:
    content = f.read()

old = """trailing: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: estado == 'completada'
                                                      ? Colors.green.shade100
                                                      : Colors.grey.shade100,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Text(estado,
                                                    style: TextStyle(
                                                        fontSize: 10,
                                                        color: estado ==
                                                                'completada'
                                                            ? Colors
                                                                .green.shade800
                                                            : Colors
                                                                .grey
                                                                .shade700)),
                                              ),"""

new = """trailing: Material(
                                                  color: Colors.transparent,
                                                  child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: estado == 'completada'
                                                      ? Colors.green.shade100
                                                      : Colors.grey.shade100,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Text(estado,
                                                    style: TextStyle(
                                                        fontSize: 10,
                                                        color: estado ==
                                                                'completada'
                                                            ? Colors
                                                                .green.shade800
                                                            : Colors
                                                                .grey
                                                                .shade700)),
                                              ),"""

if old in content:
    content = content.replace(old, new)
    with open(r"D:\araucaria_sur\lib\features\home\presentation\pages\admin\territorios_tab.dart", "w", encoding="utf8") as f:
        f.write(content)
    print("Fixed territoria_tab.dart successfully")
else:
    print("Pattern not found - showing lines around 551-572")
    lines = content.split('\n')
    for i in range(549, 575):
        print(f"{i+1}: {repr(lines[i])}")