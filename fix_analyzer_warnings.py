import os
import re

target_file = r'lib\features\home\presentation\pages\publicador\publicador_tab.dart'

with open(target_file, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Replace withOpacity with withValues(alpha: ...)
content = re.sub(r'\.withOpacity\((.*?)\)', r'.withValues(alpha: \1)', content)

# 2. Fix BuildContext sync warnings
# Change argument `BuildContext context` to nothing in `_confirmarProcesamientoTarjeta`
content = content.replace(
    'List<QueryDocumentSnapshot> direcciones,\n      BuildContext context',
    'List<QueryDocumentSnapshot> direcciones'
)

# 3. Replace .toList() in spreads. Usually looks like: ...list.toList()
# E.g. ...someVar.toList() -> ...someVar
content = re.sub(r'(\.\.\.[A-Za-z0-9_().]+)\.toList\(\)', r'\1', content)

with open(target_file, 'w', encoding='utf-8') as f:
    f.write(content)

print("Fixed publicador_tab.dart")
