---
description: Build APK de prueba (TEST-vN.apk) y lo copia a la carpeta compartida
agent: build
---

Ejecuta el flujo estándar de build de prueba para Araucaria Sur:

1. Lee `pubspec.yaml` y determiná el número de versión actual (p.ej. `1.0.2+36` → N = 36).
2. Ejecutá `flutter analyze` sobre los archivos modificados y asegurate de que no haya errores.
3. Ejecutá `flutter build apk --release`.
4. Copiá el APK generado (`build/app/outputs/flutter-apk/app-release.apk`) a `C:\Users\angel\Documents\Default Project\TEST-v{N}.apk`.
5. Verificá que el archivo exista y reportá su tamaño.

No subas versiones ni hagas commit a menos que el usuario lo pida.