---
description: Revisa los cambios pendientes y prepara un commit siguiendo las reglas del proyecto
agent: build
---

1. Ejecutá `git status` y `git diff` para ver todos los cambios.
2. Verificá que NO se haya tocado el Ecosistema principal sin causa (login, contador, historial, mantenimiento, tarjetas).
3. Verificá que los textos nuevos estén en `lib/core/l10n/app_translations.dart` en ES y PT.
4. Verificá que no haya cruces ni iconos religiosos (iconos lineales/outlined).
5. Ejecutá `flutter analyze` sobre los archivos tocados.
6. Escribí un mensaje de commit descriptivo siguiendo el estilo existente, p.ej. `feat(ecosistema2): descripción` o `fix(firebase): descripción`.
7. Stagea y commitea SOLO si el usuario lo confirma.

Nunca hagas `git push` a main directamente: el flujo es rama + Pull Request.