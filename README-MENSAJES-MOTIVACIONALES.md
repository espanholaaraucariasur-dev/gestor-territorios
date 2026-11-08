# Mensajes motivacionales — registro de trabajo

Fecha: 2026-11-08. Rama: `fix/inicio-menu-y-notificaciones`.

## Cómo es el ciclo (comportamiento aprobado)

1. El publicador termina su última tarjeta (la devuelve o la completa predicando) y queda **sin tarjetas activas**.
2. Se programa UNA tarea en `tareas_motivacionales/{email}` con `enviar_en = ahora + 10 minutos`, `enviado: false`.
3. Pasados los 10 minutos, si **sigue sin tarjetas**, recibe **UN solo mensaje**.
4. Si antes de los 10 minutos vuelve a tomar/recibir una tarjeta, el ciclo se reinicia (no se envía nada).
5. Cooldown de 2 horas entre envíos reales (`ultimo_envio`).
6. Si el publicador no abre la app: el mensaje **llega igual cuando entra**, con tope de 24 h (más viejo que eso se descarta sin enviar).
7. Los mensajes se escriben como texto normal en `configuracion/mensajes_motivacionales/mensajes` (campo `texto`, `{nombre}` se reemplaza). El comportamiento visual lo pone la app.

## Limpieza hecha hoy (producción)

Se encontraron 6 tareas colgadas (`enviar_en` en el pasado, `enviado: false`,
algunas de septiembre) que nunca se iban a enviar. Se limpiaron el 2026-11-08:
`enviado: true` + `enviar_en` borrado, para que el próximo ciclo empiece fresco.

- cortezfrancisco359@gmail.com (enviar_en 2026-10-31, verificado ok)
- luana.gouveia.stos@gmail.com (2026-09-26)
- lucasgouveiastos@gmail.com (2026-09-19)
- luisavilez021@gmail.com (fecha similar)
- oswaldo181025@gmail.com (fecha similar)
- yusbeilit@gmail.com (fecha similar)

Quedó 1 caso aparte a revisar: `joelson.stos2009@gmail.com` tiene `enviado: false`
con `ultimo_envio` del 2026-10-31 — ciclo a medio reiniciar, se resuelve solo en
el próximo evento (tomar o terminar tarjeta).

Después de la limpieza: **0 tareas colgadas** (verificado por REST).

## Fugas del ciclo (corregidas en código)

1. **Tareas que se pudren**: si `enviar_en` tiene más de 24 h y nunca se envió,
   antes quedaba colgada para siempre. Ahora `_verificarTareaPendiente()` y
   `_enviarMensajeMotivacional()` la cierran solas sin enviar.
2. **Texto vacío no cerraba la tarea**: si el mensaje elegido venía vacío, se
   hacía `return` sin marcar nada y reintentaba en cada apertura. Ahora cierra
   la tarea igual.
3. **Temporizador solo local**: el `Timer` muere si se cierra la app; la red de
   seguridad es la tarea en Firestore, que se revisa al abrir la pantalla de
   publicador (3 s después) y al cambiar el estado de tarjetas.

## Mejoras visuales (aprobadas: A + B suave)

- **A — Escenas variadas**: el fondo del diálogo cambia según el mensaje
  (amanecer, bosque, atardecer, lluvia suave). Se elige por hash del texto, así
  que cada mensaje tiene su escena estable y no sale siempre la misma.
- **B — Texto flotante suave**: la tarjeta respira (sube/baja unos píxeles con
  giro leve ~0.5°), cada mensaje con su propia deriva, ángulo y ritmo
  derivados del texto. Si el sistema tiene "quitar animaciones", queda estático.
- Los mensajes siguen siendo texto normal; la cita bíblica (`Mateo 24:14`,
  `"..."`) se detecta y se muestra en bloque aparte como ya hacía.
- Regla de contenido vigente: solo naturaleza y luz. Nada de cruces, templos,
  palomas ni simbología religiosa.

## Rotación (paso 4)

Antes: `millisecondsSinceEpoch % total` — salían casi siempre los mismos.
Ahora: cada tarea guarda `conteo_mensajes: {docId: n}` y se elige el mensaje
activo **menos usado por esa persona** (empate: el de `created_at` más viejo).
Así los 10 mensajes de `configuracion/mensajes_motivacionales/mensajes` rotan
de verdad por publicador.
