import subprocess
import os

# Use full path to flutter
flutter_path = r'C:\src\flutter\bin\flutter.bat'
os.chdir(r'D:\araucaria_sur')
result = subprocess.run(
    [flutter_path, 'analyze', 'lib\\features\\home\\presentation\\pages\\admin\\mantenimiento_tab.dart'],
    capture_output=True,
    text=True,
    cwd=r'D:\araucaria_sur'
)
output = result.stdout + result.stderr
lines = output.split('\n')
error_lines = [l for l in lines if 'error' in l.lower()]
warning_lines = [l for l in lines if 'warning' in l.lower()]
print(f'=== RESULTADO DEL ANÁLISIS ===')
print(f'Errores: {len(error_lines)}')
print(f'Warnings: {len(warning_lines)}')
print()
# Show errors
for i, line in enumerate(error_lines[:15]):
    print(f'Error {i+1}: {line.strip()}')
print()
# Show warnings
for i, line in enumerate(warning_lines[:5]):
    print(f'Warning {i+1}: {line.strip()}')