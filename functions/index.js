const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();

/**
 * Cuando se crea un documento en `notificaciones`, envia un push FCM
 * al dispositivo del destinatario (buscado por NOMBRE en `usuarios`).
 *
 * Documento esperado:
 *   { destinatario_nombre: "Carmen", titulo: "...", cuerpo: "...",
 *     tipo: "solicitud_acceso" | "solicitud_direccion" | ..., extra?: {} }
 *
 * NOTA: las notificaciones se dirigen por NOMBRE de usuario (con el que la
 * persona se registra), no por correo electrónico.
 */
exports.enviarPushNotificacion = onDocumentCreated(
  {
    document: "notificaciones/{id}",
    region: "us-central1",
  },
  async (event) => {
    const data = event.data?.data();
    if (!data) return null;

    // Preferir el nombre; si la notificacion es por rol (sin nombre concreto),
    // no se puede resolver un solo dispositivo, pero conservamos el email
    // resuelto si existe como fallback.
    const nombre = data.destinatario_nombre
      ? String(data.destinatario_nombre)
      : Array.isArray(data.destinatarios) && data.destinatarios.length > 0
        ? String(data.destinatarios[0])
        : null;
    const emailFallback = data.destinatario_email
      ? String(data.destinatario_email)
      : data.destinatario
        ? String(data.destinatario)
        : null;

    if (!nombre && !emailFallback) {
      console.log("Sin destinatario, no se envia push");
      return null;
    }

    // Buscar usuario por nombre (identidad principal) o por email (fallback).
    let ref = null;
    if (nombre) {
      const snap = await admin
        .firestore()
        .collection("usuarios")
        .where("nombre", "==", nombre)
        .limit(1)
        .get();
      if (!snap.empty) ref = snap.docs[0];
    }
    if (!ref && emailFallback) {
      const snap = await admin
        .firestore()
        .collection("usuarios")
        .where("email", "==", emailFallback)
        .limit(1)
        .get();
      if (!snap.empty) ref = snap.docs[0];
    }

    if (!ref) {
      console.log(`Usuario no encontrado: ${nombre || emailFallback}`);
      return null;
    }

    const token = ref.data().fcm_token;
    if (!token) {
      console.log(`Usuario ${nombre || emailFallback} sin fcm_token`);
      return null;
    }

    const mensaje = {
      token,
      notification: {
        title: data.titulo || "Araucaria Sur",
        body: data.cuerpo || "Tienes una nueva notificacion",
      },
      data: {
        tipo: String(data.tipo || ""),
        screen: String(data.screen || ""),
        ...(data.extra && typeof data.extra === "object"
          ? Object.fromEntries(
              Object.entries(data.extra).map(([k, v]) => [k, String(v)])
            )
          : {}),
      },
      android: { priority: "high" },
    };

    try {
      const respuesta = await admin.messaging().send(mensaje);
      console.log(`Push enviado a ${nombre || emailFallback}: ${respuesta}`);
      return respuesta;
    } catch (err) {
      // Token invalido/expirado: limpiarlo para no reintentar
      if (
        err.code === "messaging/registration-token-not-registered" ||
        err.code === "messaging/invalid-registration-token"
      ) {
        await ref.reference.update({ fcm_token: admin.firestore.FieldValue.delete() });
        console.log(`Token invalido eliminado para ${nombre || emailFallback}`);
      }
      console.error("Error enviando push:", err);
      return null;
    }
  }
);
