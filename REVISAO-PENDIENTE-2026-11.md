# Revisión del trabajo pendiente en `main` (nov 2026)

Lectura completa del proyecto: `AGENTS.md`, planes sueltos (`PLAN-*`, `PENDIENTE_NOTIFICACIONES.md`),
estado de Git y del árbol de trabajo. Esto es el punto de partida para decidir qué se termina primero.

## 1. Dónde está el proyecto hoy

- Rama `main`, último commit `c01f756` (2026-11-04): conductor con acceso rápido a tarjetas casi
  completas y progreso mensual.
- `pubspec.yaml` en **1.0.3+96**. Según `AGENTS.md`, el build 96 ya está generado
  (`app-release.aab`) y el APK de prueba `TEST-v76.apk` espera validación física.
- `dart analyze` en los archivos tocados: **0 errores, 0 warnings**. Solo quedan `info`
  preexistentes (`withOpacity` deprecado, `use_build_context_synchronously`, llaves).

## 2. Trabajo sin commitear (8 archivos modificados + 2 nuevos)

Es la **Fase 0–2 del plan de notificaciones**, ya escrita pero no cerrada:

| Archivo | Qué aporta |
|---|---|
| `lib/core/services/notification_center.dart` **(nuevo)** | Suscripción única compartida a `notificaciones` (campanilla, listado y cajón). Reintenta tras error. |
| `lib/core/services/notificacion_lectura_store.dart` **(nuevo)** | Estado de lectura **por usuario** (`notificaciones_leidas`, `_leidas_hasta`, `_limpiadas_hasta`). **Sin usar todavía en ninguna pantalla.** |
| `notificacion_service.dart` | `aplica()` tolera esquema nuevo y viejo (`destinatarios`/`destinatario_nombre`, `destinatarios_roles`/`para_roles`), trim de nombres, orden por fecha con fallback `enviado_en`, filtrado en cliente. |
| `notification_service.dart` | `onUserSignedIn()` / `onUserSignedOut()`; `initialize()` ya no pide token antes de `runApp`; web escucha `onMessage`. |
| `login_page.dart`, `splash_page.dart` | Llaman `onUserSignedIn()` tras autenticar. |
| `home_page.dart` | Cajón y campanilla usan `NotificationCenter`; `ValueKey` por usuario; logout limpia token + suscripción. |
| `notificaciones_widget.dart` | Badge con estado de error visible y acciones con manejo de fallo. |
| `devueltas_tab_original.dart` | Escribe `destinatarios_roles` (fin del desajuste con `para_roles`). |
| `firestore.rules` | `update/delete` en `notificaciones` ya no exigen `uid == id`. **Sin desplegar.** |

### Huecos que encontré al revisar

1. **`NotificacionLecturaStore` no está conectado.** `marcarLeidas`/`limpiar` de
   `NotificacionService` siguen escribiendo `leida` en el documento **compartido**: un admin marca
   leído y se le apaga a todos. Es el motivo por el que se creó el store.
2. **`firestore.rules` no está desplegado** → "Leer todas" y "Limpiar" fallan en producción hasta
   que se ejecute `firebase deploy --only firestore:rules`.
3. **Todo esto está sobre `main`**, contra la regla del proyecto (rama + PR). Conviene mover a
   `feat/notificaciones-fase-1-2` antes de seguir.
4. **`functions/`**: 95 archivos sin versionar, casi todos scripts de diagnóstico sueltos
   (`diag-*.js`, `auditar-*.js`, `contar-*.js`…). Son de usar y tirar.
5. **Push real sigue bloqueado** por el plan Spark → Blaze (Fase 4 del plan).

## 3. Pendientes por orden de valor

1. **Cerrar notificaciones Fase 1–2** (2–4 h): conectar `NotificacionLecturaStore` en
   `notificaciones_widget.dart` y `home_page.dart`, desplegar reglas, prueba de matriz
   (confirmar tarjeta → contador 0 → badge → "Leer todas" sin afectar a otros).
2. **Prueba física offline F1–F3** (`PLAN-MODO-OFFLINE.md`): modo avión en Android — cargar
   tarjetas, marcar una dirección, transferir, reconectar y verificar Firestore + biometría.
3. **`PLAN-AJUSTES.md`** — 4 puntos: desglose en progreso mensual, devolución automática
   programable, pestaña de temporales oculta + comentarios con autor/fecha, y mapa que cargue
   **todas** las direcciones de la tarjeta.
4. **Limpieza**: `functions/*.js` de diagnóstico, `fix_*.py` / `check_errors*.py` en la raíz,
   `build.log`, `chat,openCode.md.txt`.
5. **Fase 3 motivacional** y **Fase 4 push** del plan de notificaciones (requiere Blaze).

## 4. Recomendación

Empezar por el punto 1: es código ya escrito y sin verificar, deja la campanilla correcta y es
lo único que hoy puede estar mostrando datos cruzados entre usuarios.
