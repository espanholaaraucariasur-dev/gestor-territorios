# AGENTS.md — gestor-territorios

Proyecto Flutter/Firebase para la Congregación Española Araucaria Sur (Testigos de Jehová). Repositorio: https://github.com/espanholaaraucariasur-dev/gestor-territorios

## Reglas generales
- NO usar cruces ni iconos religiosos (Icons.church, etc.). El salón se llama "Salón del Reino" y su logo es "JW".
- Iconos siempre en estilo lineal (outlined), manteniendo armonía con el resto de la app.
- Todo el código con texto en ES y PT a través de `lib/core/l10n/app_translations.dart` (usar `context.t('clave')`).
- Mantener las convenciones de estilo existentes. No agregar comentarios salvo cuando aporten.

## Trabajo en equipo (Git por ramas + PR)
- El equipo trabaja en **ramas** (p.ej. `feat/...`, `fix/...`), NUNCA directo en `main`.
- Flujo: `git checkout -b feat/x` → cambios → `git push origin feat/x` → Pull Request en GitHub.
- El líder revisa y mergea. La rama `main` es del líder.
- `git pull origin main` al empezar cada sesión para estar al día.
- Comandos de proyecto disponibles en opencode: `/build-apk`, `/deploy-web`, `/commit`.
- Agente revisor disponible: `revisor` (verifica las reglas de oro antes de mergear).

## Versiones y flujo de trabajo
- Play Console publica la app como build **27** (ya subidо). El `.aab` para subir se genera con ese número y solo se debe renumerar al pedirlo PCD.
- Desarrollo local: pubspec.yaml en **1.0.2+33** o más, generando `TEST-vN.apk` (N = build actual).
- Flujo habitual: modificar código → `flutter analyze` de los archivos tocados → bump de versión → `flutter build apk --release` → copiar APK a `C:\Users\angel\Documents\Default Project\TEST-vN.apk` → `git add` + `git commit` + `git push origin main`.
- Regla de oro: probar con APK local antes de subir `.aab` a Play Console. No subir sin confirmación del usuario.

## Arquitectura / aislamiento
- **Ecosistema principal** (funciona y no se debe romper): login, contador de asistencia, historial (`asistencia_historial`), mantenimiento, tarjetas/territorios.
- **Ecosistema 2** (front en desarrollo, aislado): `lib/features/ecosistema2/`. No debe importar ni modificar los features existentes (excepto `home_page.dart` para el ítem del menú). Sin backend aún.
- NO tocar los archivos del ecosistema principal sin causa; verificar con `flutter analyze` que nada se rompe.

## Archivos clave
- `lib/core/constants/firebase_config.dart` — `FirebaseConfig.opciones` (config por plataforma; Android no usa la web).
- `lib/features/auth/presentation/pages/login_page.dart` — login + migración automática a Firebase Auth.
- `lib/features/home/presentation/pages/asistencia/contador.dart` — contador (fecha con día de la semana, sin nombre de usuario).
- `lib/features/home/presentation/pages/asistencia/contador_historial.dart` — historial (leer/reenviar, sin editar).
- `lib/features/home/presentation/pages/admin/mantenimiento_tab.dart` — mantenimiento (incluye "Limpiar historial del contador").
- `lib/features/ecosistema2/presentation/` — panel principal, mantenimiento y placeholders del Ecosistema 2.
- `lib/core/l10n/app_translations.dart` — traducciones ES/PT (claves `eco2_*` del Ecosistema 2).
- `.opencode/` — configuración de opencode del proyecto (MCP, comandos `/build-apk`, `/deploy-web`, `/commit`, agente `revisor`).

## Base de datos (Firestore)
- Colecciones usadas: `usuarios`, `territorios` (+`tarjetas`), `direcciones_globales`, `direcciones_removidas`, `configuracion`, `configuraciones`, `notificaciones`, `estadisticas`, `estadisticas_mensuales`, `sistema`, `solicitudes_localizador`, `tareas_motivacionales`, `asistencia_historial`.
- Regla actual: `match /{document=**} { allow read, write: if request.auth != null; }` (todo autenticado).

## Entorno
- Windows, Flutter en `C:\src\flutter\bin\flutter.bat`, proyecto en `D:\araucaria_sur`.
- APKs de prueba en `C:\Users\angel\Documents\Default Project\TEST-vN.apk`.
- Servidor opencode mobile: `opencode serve --hostname 0.0.0.0 --port 4096` (password vía `OPENCODE_SERVER_PASSWORD`).
- **Puente Telegram** (enviar instrucciones al opencode desde el bot): script `C:\Users\angel\AppData\Local\Temp\opencode\telegram_bridge.ps1` — long polling, usa `opencode run --dir D:\araucaria_sur` con sesión propia (NO chocar con el TUI); offset en `tg_offset.txt`, log en `bridge_log.txt`. Reiniciar tras reinicio de PC: `Start-Process powershell -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File","C:\Users\angel\AppData\Local\Temp\opencode\telegram_bridge.ps1" -WindowStyle Hidden`.
- Servidor APK local (si está corriendo): `http://192.168.100.122:8000`.
- Terminal de despliegue: puertos 4096 (opencode) y 8000 (APK) abiertos por `abrir_puertos.bat`.

## Entrega de APKs al celular (OneDrive + Telegram)
- **Mecanismo estándar (confirmado por el usuario)**: la carpeta `C:\Users\angel\Documents\Default Project` ya está compartida con OneDrive. Solo hay que guardar el APK ahí (`TEST-vN.apk`) y OneDrive lo sube solo a la nube. NO copiar a `C:\Users\angel\OneDrive` manualmente.
- Aviso por Telegram al bot `@Araucaria_sur_bot` (chat 6281442034) cuando haya APK nuevo.
- El celular descarga desde la app **OneDrive** (misma cuenta), no por link público (no generamos enlaces públicos por OAuth).
- Fallback local: servidor APK `http://100.114.25.100:8000/TEST-vN.apk` vía Tailscale. El enlace `https://onedrive.live.com/?v=1&view=managestorage` sirve para liberar cupo (vaciar papelera).

## Acceso remoto (Tailscale)
- VPN Tailscale, plan free (mejor opción para un teléfono; reemplazó a Quick Tunnel/ngrok).
- PC = IP Tailscale `100.114.25.100` (fija). Teléfono entra a OpenCode Mobile con `http://100.114.25.100:4096` (misma cuenta Tailscale en ambos).
- Verificado: el servidor responde por Tailscale en `100.114.25.100:4096`.
- No requiere cambios de DNS ni apertura de puertos. Solo instalar/abrir Tailscale en el teléfono.