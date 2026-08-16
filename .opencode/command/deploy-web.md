---
description: Deploy de la versión web a Firebase Hosting
agent: build
---

Ejecuta el flujo de despliegue web de Araucaria Sur:

1. Ejecutá `flutter build web --release`.
2. Ejecutá `firebase deploy --only hosting`.
3. Verificá que el sitio responda: https://territorio-sur-8b72c.firebaseapp.com/
4. Reportá el resultado (URL + estado).

No toques código ni hagas commits.