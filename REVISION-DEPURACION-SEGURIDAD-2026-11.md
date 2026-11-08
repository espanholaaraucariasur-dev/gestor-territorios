# Revisión de depuración y seguridad — araucaria_sur (nov 2026)

Rama revisada: `feat/notificaciones-fase-1-2` (commit `96ffc9c`).
Alcance: depuración (errores silenciados, fugas, estados cruzados) y seguridad
(reglas Firestore, secretos, control de acceso). Sin cambios de código todavía.

---

## 1. `dart analyze lib` — línea base

**0 errores, 0 warnings.** 318 `info`, de los cuales:

| Regla | Casos |
|---|---|
| `deprecated_member_use` (`withOpacity`, `Radio.onChanged`) | 150 |
| `prefer_const_constructors` / literales / declaraciones | 78 |
| `use_build_context_synchronously` | 38 |
| `curly_braces_in_flow_control_structures` | 28 |
| `unnecessary_to_list_in_spreads` | 9 |
| `avoid_print` | 5 |
| otros (menores) | 10 |

Nada de esto rompe el build. El riesgo real está más abajo, en lo que el
analizador no ve.

---

## 2. Depuración — hallazgos por gravedad

### 🔴 D1. "Leer todas" y "Limpiar" siguen borrando notificaciones de todos

`lib/core/services/notificacion_service.dart:394` y `:411`.

```dart
static Future<void> marcarLeidas(PerfilNotificacion perfil) async {
  final docs = await _obtenerDocs(perfil);
  // batch.update(doc.reference, {'leida': true});   ← documento COMPARTIDO
}

static Future<void> limpiar(PerfilNotificacion perfil) async {
  // batch.delete(doc.reference);                    ← lo BORRA para todos
}
```

`NotificacionLecturaStore` ya existe y ya está conectado en lectura
(`notificaciones_widget.dart:26,37`, `home_page.dart:585`), pero estas dos
acciones **no lo usan**: escriben en el documento compartido. Un admin que
pulsa "Limpiar" borra la notificación del resto de los admins.

Es el hueco nº1 que ya señalaba `REVISION-PENDIENTE-2026-11.md`, y el más
visible en producción.

**Arreglo:** `marcarLeidas` → `lectura.marcarTodas(fecha)` y `limpiar` →
`lectura.limpiarHasta(fecha)`; el documento compartido no se toca.

### 🔴 D2. La transferencia de tarjeta no es atómica

`lib/core/utils/transferencia_tarjeta.dart`. Lee el dueño actual, pide
confirmación y escribe. Entre la lectura y la escritura no hay transacción ni
`updated_at` condicional: dos admins transfiriendo la misma tarjeta a la vez
dejan un estado indeterminado y el "dueño anterior" al que se le notifica
puede ser el equivocado. Además, toda la autorización se decide **en el
cliente** (ver S2).

**Arreglo:** `runTransaction` que relea `asignado_a`, o `update` con
precondición sobre el valor leído. Hoy el proyecto no usa ninguna transacción
en `lib/` (1 sola referencia en total).

### 🟠 D3. 37 `catch` vacíos — fallos invisibles

Los más delicados:

| Archivo | Qué se traga |
|---|---|
| `login_page.dart:92,203,704` | fallo al escribir token FCM o al cargar el perfil |
| `splash_page.dart:157` | fallo de arranque de sesión |
| `transferencia_tarjeta.dart:227` | la notificación al nuevo dueño |
| `notification_service.dart:243` | `Firebase.initializeApp` en background |
| `auto_asignador_service.dart:307,381` | la notificación de auto-asignación |
| `auto_return_service.dart:219,234` | notificación de devolución automática |

Los best-effort de notificación están bien documentados como tales. Los de
`login_page`/`splash_page` no: un usuario puede quedar con sesión sin token y
sin rastro en consola.

### 🟠 D4. Lecturas completas de colecciones

- `notificacion_service.dart:_obtenerDocs` → `collection('notificaciones').get()`
  **sin filtro ni límite**, en cada pulsación. Con años de historial eso es
  costo y latencia crecientes.
- Varias pantallas hacen `orderBy` sin `limit` (`admin_tab`, `usuarios_tab`,
  `comunicacion_tab`, `territorios_tab`, `contador_historial`).

### 🟡 D5. Sin pruebas

`test/` no cubre nada de lo tocado en esta rama. `NotificacionLecturaStore`
(`estaLeida`, `estaOculta`, `_leidas_hasta`) es lógica pura y sería el primer
lugar donde poner tests de widget/unitarios baratos.

### 🟡 D6. `avoid_print` (5 casos) y deprecaciones

Los 5 `print` van a consola de producción; cambiar por `debugPrint`.
`withOpacity` → `withValues()` se puede hacer con un reemplazo masivo, sin
riesgo funcional (150 casos, cosmético).

---

## 3. Seguridad — hallazgos por gravedad

### 🔴 S1. Las reglas de Firestore no protegen nada — ✅ reescritas y probadas

`firestore.rules` original: **todas** las colecciones eran
`allow read, write: if sesionReal()`. Cualquier usuario autenticado podía
escribir `usuarios`, `territorios`, `tarjetas`, `direcciones_globales` y el
resto, incluido ponerse `es_admin: true` en su propio documento.

**Estado: reescritas en `firestore.rules` y cubiertas por
`test/reglas_firestore.test.cjs` (22 casos, todos verdes contra el emulador).**
Todavía **sin desplegar**.

Qué cambia:

| Antes | Ahora |
|---|---|
| `usuarios`: `write` para cualquier sesión | `update` propio solo con campos de preferencia (`fcm_token`, estado de lectura de notificaciones, idioma, familia, funciones del eco2). Ningún rol está en esa lista: nadie se asciende. |
| `notificaciones`: `update/delete` para cualquiera | `create` para cuentas aprobadas; `update/delete` solo admin principal. El estado de lectura es por usuario (D1). |
| `territorios`/`tarjetas`: `write` para cualquiera | `write` para admin / admin de territorios / auditor. El publicador toma y actualiza tarjetas, pero no las borra ni crea territorios. |
| `configuracion`: `write` para cualquiera | Solo admin. |
| Comodín `{document=**}` con `write` abierto | Lectura para cuentas aprobadas, escritura solo para roles de gestión. |

**Admin principal:** `angelrivas027@gmail.com`, comprobado contra el correo
**verificado** del token de Auth (`esAdminPrincipal()`). Es el único rol que
las reglas pueden validar sin leer `usuarios/{uid}`, así que es el que respalda
las operaciones sensibles: bajas de usuario, purga de notificaciones y
configuración.

**Deuda declarada:** mientras los documentos de usuario **no tengan el uid de
Auth como id**, las reglas no pueden comprobar quién es admin sin leer el
mismo documento que se está escribiendo, y en el emulador eso desestabiliza la
evaluación (ver la nota de oro en `firestore.rules`). Por eso hoy el cambio de
roles de *otros* usuarios está abierto a cualquier sesión real y la
autorización real vive en la UI. Se cierra con la migración `usuarios/{uid}`.

**Para desplegar** (hacerlo después de probar en un proyecto de staging):

```
firebase deploy --only firestore:rules
```

### 🔴 S2. Llaves de API de pago dentro del binario

`lib/core/config/app_secrets.dart` (ignorado por git — bien, **no está en el
historial**: verificado con `git log --all -S`), pero sus valores se compilan
en el APK/AAB:

- `geminiApiKey = 'AIzaSyAAF5…'`
- `groqSyncKey = 'gsk_u539…'`

Cualquiera que descompile la app usa esas llaves a tu costa. El propio
`groq_reporte_service.dart` ya admite `--dart-define=GROQ_API_KEY`, así que el
camino existe: **rotar las dos llaves y pasar a `--dart-define` / proxy en
Cloud Functions**, dejando la plantilla sin valores.

El `mapboxToken` es público por diseño (`pk.`) y está restringido por URL, así
que ese es aceptable.

### 🟠 S3. Las `apiKey` de Firebase en el repo no son un secreto

`firebase_options.dart` y `.firebaserc` con `territorio-sur-8b72c`: normal y
público por diseño. Lo que protege el proyecto son las reglas — que hoy no
protegen (S1). No hay nada que rotar aquí.

### 🟠 S4. Sin App Check ni límites de abuso

No hay `FirebaseAppCheck` en `lib/`. Cualquiera con el `apiKey` web (público)
puede hablar con Firestore/Auth desde fuera de la app. Activar App Check
(reCAPTCHA v3 en web, Play Integrity en Android) corta el abuso automatizado y
es lo que hace que S1 importe menos.

### 🟡 S5. Contraseña de keystore y build

`android/app/araucaria_sur.jks` y `key.properties` están correctamente en
`.gitignore`. Confirmar que `key.properties` no viaja en artefactos de CI y que
la contraseña del keystore está en un gestor, no en `AGENTS.md`.

### 🟡 S6. Reglas de Storage

`firebase.json` no declara `storage`. Si se usa Firebase Storage para folletos,
hay que revisar si tiene reglas por defecto (`allow read, write: if
request.auth != null` es el default del CLI) — mismo patrón que S1.

---

## 4. Orden propuesto

| # | Tarea | Esfuerzo | Por qué primero |
|---|---|---|---|
| 1 | D1: `marcarLeidas`/`limpiar` contra `NotificacionLecturaStore` | 1 h | Bug visible, datos cruzados entre usuarios |
| 2 | S2: rotar Groq + Gemini y pasar a `--dart-define` | 1 h | Dinero real expuesto en cada APK |
| 3 | D3: revisar los `catch` de `login_page`/`splash_page` | 1 h | Fallos de sesión sin rastro |
| 4 | S1: endurecer `firestore.rules` (empezando por `usuarios`) | 3–6 h | Es el agujero de fondo |
| 5 | S4: App Check | 2 h | Corta abuso externo |
| 6 | D2: transferencia transaccional | 2 h | Carreras entre admins |
| 7 | D4/D5/D6: límites, tests del store, deprecaciones | 4 h | Deuda, no urgencia |

El despliegue de reglas de esta rama **no** debe hacerse antes del punto 4.
