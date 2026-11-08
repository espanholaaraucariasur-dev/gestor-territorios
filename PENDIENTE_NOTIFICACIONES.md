# EN ESPERA — Plan de notificaciones

**Estado:** pausado. El usuario decidió priorizar Estadísticas.
**Decisiones tomadas:** sí, ya están confirmadas. No hace falta volver a preguntar.

---

## Decisión 1 — Disparo del mensaje motivacional

**Regla elegida:** el evento es la **confirmación/devolución de una tarjeta**, y la
condición es que el contador de tarjetas activas del publicador pase a **cero**.

> Si el publicador entrega una tarjeta pero aún le quedan 2 por trabajar, no se
> manda nada. "¡Buen trabajo completando tu territorio!" sería confuso.

Consecuencia técnica: `_programarMensajeMotivacional` deja de depender de que el
usuario esté en cero tarjetas al momento de correr. Se dispara desde la
confirmación, y *después* se consulta el contador. Si no es cero, no se programa.

## Decisión 2 — Alcance del push

**Alcance acotado a individuals.** Solo se arregla el registro/actualización/
refresco del token FCM y la entrega a usuario concreto.

Fuera de alcance por ahora: fan-out a múltiples roles, multi-dispositivo
(`fcm_tokens` como array). Se añade después de validar la base.

---

## Diagnóstico (19 defectos, ya identificado — no volver a analizar)

### A. El número no aparece — `notificaciones_widget.dart`
1. `streamConteo` se crea dentro de `build()` (`:21`) → re-suscribe en cada
   rebuild sobre la colección `notificaciones` **completa**
   (`notificacion_service.dart:292-295`, sin `limit`).
2. El badge no maneja `snap.hasError` (`:23`): un fallo transitorio muestra `0`
   en silencio. La hoja sí lo maneja (`:277`).
3. Desajuste de nombres: `_aplica` compara con `==` contra `perfil.nombre`, que
   sí viene `.trim()` (`notificacion_service.dart:277`), pero
   `_construirDatosNotificacion` guarda los destinatarios **sin trimear**
   (`:81-84`).
4. `streamNotificaciones` hace `.take(50)` sobre una colección **global** por
   fecha (`:332`) → el badge marca >0 y la lista sale vacía.
5. `marcarLeidas`/`limpiar` usan `.take(200)` (`:376`).
6. `orderBy('created_at')` sin `limit`: los docs sin ese campo se excluyen.

### B. No llegan las alertas
7. `main.dart:43/45` llama `initialize()` **antes de `runApp`** →
   `_saveTokenToFirestore` ve `currentUser == null` y retorna
   (`notification_service.dart:136`). **El `fcm_token` nunca se guarda.**
8. En web, `initialize()` hace `return` temprano (`notification_service.dart:32`)
   → nunca suscribe `onMessage` ni `onMessageOpenedApp`.
9. `functions/index.js` resuelve un solo usuario y un solo token.
10. Los broadcasts por rol nunca hacen push: `destinatario_nombre` es `null`
    (`notificacion_service.dart:103-104`) y `index.js` no lee
    `destinatarios_roles` → "Sin destinatario" (`:40-43`).
11. `index.js:31-32` usa `destinatarios[0]` como fallback de email, pero ahí van
    **nombres**.

### C. Mensaje motivacional
12. `MensajeMotivacionalDialog.mostrar` solo se invoca desde `_alTocar`
    (`notificaciones_widget.dart:154`) → **no hay alerta automática**.
13. Solo se programa con cero tarjetas activas (`publicador_tab.dart:428`).
14. Ciclo muerto: `_reiniciarCicloMotivacional` deja `enviado: false` con
    `enviar_en` borrado (`:402-406`); luego `:436-439` retorna "ya hay tarea
    pendiente" y `_verificarTareaPendiente` retorna por `enviar_en` null (`:114`).
15. `msgsSnap.docs.isEmpty` → `return` **sin marcar la tarea** (`:521`): bloquea
    los reintentos para siempre, en silencio.
16. El temporizador es solo cliente (`Timer` `:392`) y se cancela en `dispose()`
    (`:130`).

### D. Esquema
17. `devueltas_tab_original.dart` (importado por `admin_territorios_tab.dart:4`)
    escribe con `para_roles` (`:210`, `:355`, `:365`) mientras el servicio lee
    `destinatarios_roles` (`notificacion_service.dart:303`) → invisibles para
    todos.
18. `ArgumentError` si no hay destinatarios (`:91`) sin capturar en varios call
    sites → candidato del `Uncaught Error`.
19. El badge no lleva `ValueKey` (`home_page.dart:796`): al cambiar de usuario el
    `State` puede no reconstruirse.

---

## Fases (para cuando se retome)

**Fase 0 — Datos.** Migrar `para_roles` → `destinatarios_roles`; sembrar
`configuracion/mensajes_motivacionales/mensajes` con `activo: true`; impedir
escrituras directas con `add()` fuera del servicio.

**Fase 1 — Badge robusto.** Crear `notification_center.dart` (singleton) con una
sola suscripción de por vida fuera de `build()`; badge y lista del mismo stream;
normalizar nombres; índices compuestos en vez de traer la colección entera;
propagar `hasError` con reintento.

**Fase 2 — Alerta en tiempo real.** `NotificationCenter` expone
`Stream<NotificacionNueva>` con dedupe por doc id y `visto` persistido; alerta
automática (Snackbar/diálogo) sin abrir la campana; el motivacional se muestra
directo; `ValueKey` por usuario en `home_page.dart:796`.

**Fase 3 — Ciclo motivacional.** Máquina de estados en Firestore
(`programada` → `enviable` → `enviada`) con `intentos` y `ultimo_error`; worker
programado para que funcione con la app cerrada; disparo desde la confirmación
con condición de contador == 0; marcar `enviado` aunque no haya mensajes.

**Fase 4 — Push (solo individuals).** Mover el registro del token a
`authStateChanges`/post-login con reintento; suscribir `onMessage` y
`onMessageOpenedApp` en web; no enviar push a quien originó la notificación.

**Fase 5 — Cierre.** `firestore.rules`, índices, matriz de prueba:
confirmar tarjeta → contador 0 → alerta en vivo + badge + push en el otro
dispositivo → tap navega.

## Archivos

| Archivo | Fases |
|---|---|
| `lib/core/services/notificacion_service.dart` | 0, 1, 3 |
| `lib/core/services/notification_center.dart` **(nuevo)** | 1, 2 |
| `lib/features/home/presentation/widgets/notificaciones_widget.dart` | 1, 2 |
| `lib/features/home/presentation/pages/publicador/publicador_tab.dart` | 3 |
| `lib/core/services/notification_service.dart` | 4 |
| `lib/main.dart` | 4 |
| `functions/index.js` | 4 |
| `lib/features/home/presentation/pages/admin/devueltas_tab_original.dart` | 0 |
| `lib/features/home/presentation/pages/home_page.dart` | 2 |
| `firestore.rules` / `firestore.indexes.json` | 5 |
| `configuracion/mensajes_motivacionales/mensajes` | 0 |
