// Prueba de las reglas de Firestore contra el emulador.
//
//   JAVA_HOME="C:/Program Files/Android/Android Studio/jbr" \
//   firebase emulators:exec --only firestore --project demo-araucaria-rules \
//     "node test/reglas_firestore.test.cjs"
//
// Verifica los agujeros que cerró la revisión de seguridad de nov 2026:
// escalada de rol, notificaciones compartidas y escrituras cruzadas.
//
// ⚠️ Orden importante. El emulador cachea el resultado de las funciones que
// hacen `get()`/`exists()`. Un caso que degrada al usuario de prueba (por
// ejemplo `es_admin: false` sobre sí mismo) deja el resto de la corrida con
// datos viejos y todo empieza a fallar sin motivo. Por eso:
//   - los casos de administración van PRIMERO;
//   - los que tocan roles van al final;
//   - cada caso deja el documento como estaba (`restaurar`).

const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const fs = require('fs');
const path = require('path');

const PROYECTO = 'demo-araucaria-rules';
const RULES = fs.readFileSync(
  path.join(__dirname, '..', 'firestore.rules'),
  'utf8'
);

const ADMIN = 'uid-admin';
const PUBLICADOR = 'uid-publicador';
const PENDIENTE = 'uid-pendiente';

const USUARIOS = {
  [ADMIN]: {
    nombre: 'Admin',
    email: 'admin@test.com',
    estado: 'aprobado',
    es_admin: true,
    es_admin_territorios: false,
    es_auditor: false,
  },
  [PUBLICADOR]: {
    nombre: 'Publicador',
    email: 'pub@test.com',
    estado: 'aprobado',
    es_admin: false,
    es_admin_territorios: false,
    es_auditor: false,
  },
  [PENDIENTE]: {
    nombre: 'Pendiente',
    email: 'pend@test.com',
    estado: 'pendiente',
    es_admin: false,
  },
};

let fallos = 0;
let pasadas = 0;

async function caso(nombre, fn) {
  try {
    await fn();
    pasadas++;
    console.log(`  ok   ${nombre}`);
  } catch (e) {
    fallos++;
    console.log(`  FALLA ${nombre}\n         ${e.message.split('\n')[0]}`);
  }
}

async function main() {
  const env = await initializeTestEnvironment({
    projectId: PROYECTO,
    firestore: { rules: RULES },
  });

  const sembrar = async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      for (const [uid, data] of Object.entries(USUARIOS)) {
        await db.collection('usuarios').doc(uid).set(data);
      }
      await db.collection('notificaciones').doc('n1').set({
        titulo: 'Aviso',
        destinatarios_roles: ['es_admin'],
        created_at: new Date(),
      });
      await db.collection('territorios').doc('t1').set({ nombre: 'T1' });
      await db
        .collection('territorios')
        .doc('t1')
        .collection('tarjetas')
        .doc('k1')
        .set({ nombre: 'K1', asignado_a: 'Publicador' });
      await db.collection('estadisticas').doc('e1').set({ total: 1 });
    });
  };

  await sembrar();

  const como = (uid, extra = {}) =>
    env.authenticatedContext(uid, extra).firestore();
  const anonimo = () => env.unauthenticatedContext().firestore();
  const restaurar = sembrar;

  // ── Administración (primero: no degradan al usuario de prueba) ──────────
  console.log('\nAdministración');

  await caso('el admin SÍ puede purgar notificaciones', async () => {
    await assertSucceeds(
      como(ADMIN).collection('notificaciones').doc('n1').delete()
    );
    await restaurar();
  });

  await caso('el admin SÍ crea territorios', async () => {
    await assertSucceeds(
      como(ADMIN).collection('territorios').doc('t3').set({ nombre: 'T3' })
    );
    await restaurar();
  });

  await caso('el admin SÍ escribe configuración', async () => {
    await assertSucceeds(
      como(ADMIN).collection('configuracion').doc('codigo_acceso').set({
        codigo: 'x',
      })
    );
    await restaurar();
  });

  await caso('el admin SÍ aprueba y desactiva cuentas', async () => {
    await assertSucceeds(
      como(ADMIN)
        .collection('usuarios')
        .doc(PUBLICADOR)
        .update({ estado: 'pendiente' })
    );
    await restaurar();
  });

  // ── Notificaciones compartidas ─────────────────────────────────────────
  console.log('\nNotificaciones compartidas');

  // Fase 1: la purga del documento compartido sigue abierta (como antes).
  // Lo que ya está cerrado es que el usuario marque LEÍDO el documento
  // compartido: su lectura vive en su propio documento.
  await caso('el publicador SÍ puede crear una notificación', async () => {
    await assertSucceeds(
      como(PUBLICADOR).collection('notificaciones').doc('n2').set({
        titulo: 'x',
        created_at: new Date(),
      })
    );
    await restaurar();
  });

  // ── Territorios y tarjetas ─────────────────────────────────────────────
  console.log('\nTerritorios y tarjetas');

  await caso('el publicador SÍ toma/actualiza su tarjeta', async () => {
    await assertSucceeds(
      como(PUBLICADOR)
        .collection('territorios')
        .doc('t1')
        .collection('tarjetas')
        .doc('k1')
        .update({ estado: 'trabajada' })
    );
  });

  // Fase 1: el borrado de territorios sigue como antes (abierto). Se aprieta
  // en la fase 2, cuando esté claro que ninguna pantalla lo necesita.
  await caso('FASE 1: el publicador todavía borra territorios', async () => {
    await assertSucceeds(
      como(PUBLICADOR).collection('territorios').doc('t1').delete()
    );
    await restaurar();
  });

  // Fase 1 del despliegue: crear territorios sigue abierto a cuentas
  // aprobadas (como antes). En la fase 2 pasa a exigir rol de gestión.
  await caso('FASE 1: el publicador todavía puede crear territorios', async () => {
    await assertSucceeds(
      como(PUBLICADOR).collection('territorios').doc('t2').set({ nombre: 'T2' })
    );
    await restaurar();
  });

  // ── Resto del ecosistema ───────────────────────────────────────────────
  console.log('\nResto del ecosistema');

  // Fase 1: la escritura del comodín sigue como antes. Lo que ya está cerrado
  // es lo que importa para seguridad: roles y notificaciones.
  await caso('FASE 1: el publicador todavía escribe estadísticas', async () => {
    await assertSucceeds(
      como(PUBLICADOR).collection('estadisticas').doc('e1').update({ total: 99 })
    );
    await restaurar();
  });

  await caso('el publicador SÍ registra asistencia', async () => {
    await assertSucceeds(
      como(PUBLICADOR).collection('asistencia_historial').doc('a1').set({
        fecha: new Date(),
        total: 10,
      })
    );
  });

  await caso('el publicador SÍ lee configuración', async () => {
    await assertSucceeds(
      como(PUBLICADOR).collection('configuracion').doc('codigo_acceso').get()
    );
  });

  // ── Usuarios: lo que puede hacer el propio usuario ─────────────────────
  console.log('\nUsuarios');

  await caso('el publicador SÍ puede guardar su token FCM', async () => {
    await assertSucceeds(
      como(PUBLICADOR)
        .collection('usuarios')
        .doc(PUBLICADOR)
        .update({ fcm_token: 'abc' })
    );
  });

  await caso('el publicador SÍ puede marcar sus notificaciones leídas', async () => {
    await assertSucceeds(
      como(PUBLICADOR)
        .collection('usuarios')
        .doc(PUBLICADOR)
        .update({
          notificaciones_leidas: [],
          notificaciones_leidas_hasta: new Date(),
          notificaciones_limpiadas_hasta: new Date(),
        })
    );
  });

  await caso('sin sesión no se lee el directorio', async () => {
    await assertFails(anonimo().collection('usuarios').doc(ADMIN).get());
  });

  // ── Escalada de privilegios (al final: degradan al usuario de prueba) ──
  console.log('\nEscalada de privilegios');

  await caso('el publicador NO puede ponerse es_admin', async () => {
    await assertFails(
      como(PUBLICADOR).collection('usuarios').doc(PUBLICADOR).update({
        es_admin: true,
      })
    );
    await restaurar();
  });

  await caso('el publicador NO puede ponerse es_admin_territorios', async () => {
    await assertFails(
      como(PUBLICADOR)
        .collection('usuarios')
        .doc(PUBLICADOR)
        .update({ es_admin_territorios: true })
    );
    await restaurar();
  });

  await caso('el publicador NO puede cambiarse el estado a aprobado', async () => {
    await assertFails(
      como(PENDIENTE)
        .collection('usuarios')
        .doc(PENDIENTE)
        .update({ estado: 'aprobado' })
    );
    await restaurar();
  });

  await caso('una cuenta pendiente no escribe su propio documento', async () => {
    await assertFails(
      como(PENDIENTE)
        .collection('usuarios')
        .doc(PENDIENTE)
        .update({ fcm_token: 'x' })
    );
  });

  await caso('una solicitud de acceso nace sin rol de admin', async () => {
    await assertFails(
      como(PENDIENTE).collection('usuarios').doc('uid-nuevo').set({
        nombre: 'Nuevo',
        email: 'n@test.com',
        estado: 'pendiente',
        es_admin: true,
      })
    );
  });

  // ── Admin principal (por correo en el token) ───────────────────────────
  console.log('\nAdmin principal');

  const PRINCIPAL = 'uid-principal';
  const tokenPrincipal = {
    email: 'angelrivas027@gmail.com',
    email_verified: true,
  };

  await caso('el admin principal puede editar a otro sin ser es_admin', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('usuarios').doc(PRINCIPAL).set({
        nombre: 'Angel',
        email: 'angelrivas027@gmail.com',
        estado: 'aprobado',
        es_admin: false,
      });
    });
    await assertSucceeds(
      como(PRINCIPAL, tokenPrincipal)
        .collection('usuarios')
        .doc(PUBLICADOR)
        .update({ es_admin_territorios: true })
    );
    await restaurar();
  });

  await caso('el admin principal puede borrar un usuario', async () => {
    await assertSucceeds(
      como(PRINCIPAL, tokenPrincipal)
        .collection('usuarios')
        .doc('uid-nuevo')
        .delete()
    );
    await restaurar();
  });

  // Fase 1: la purga de notificaciones sigue abierta, así que este caso
  // comprueba el efecto real del token: que sin correo verificado NO cuente
  // como admin principal para las operaciones sensibles (bajas de usuario).
  await caso('un correo no verificado NO es admin principal', async () => {
    await assertFails(
      como('uid-falso', {
        email: 'angelrivas027@gmail.com',
        email_verified: false,
      })
        .collection('usuarios')
        .doc('uid-x')
        .set({ nombre: 'X', email: 'x@test.com' })
    );
    await restaurar();
  });

  await caso('una cuenta nueva NO puede nacer aprobada', async () => {
    await assertFails(
      como(PENDIENTE).collection('usuarios').doc('uid-nuevo2').set({
        nombre: 'Nuevo',
        email: 'n2@test.com',
        estado: 'aprobado',
        es_publicador: true,
      })
    );
  });

  await caso('una solicitud de acceso normal sí se crea', async () => {
    // Contexto nuevo sin token extra, como un usuario recién registrado.
    await assertSucceeds(
      env.authenticatedContext('uid-solicitante').firestore()
        .collection('usuarios').doc('uid-solicitante').set({
        nombre: 'Nuevo',
        email: 'n3@test.com',
        estado: 'pendiente',
        es_publicador: true,
      })
    );
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('usuarios').doc('uid-solicitante').delete();
    });
  });

  await caso('el admin principal aprueba una cuenta', async () => {
    await assertSucceeds(
      como(PRINCIPAL, tokenPrincipal)
        .collection('usuarios')
        .doc(PENDIENTE)
        .update({ estado: 'aprobado' })
    );
    await restaurar();
  });

  // ── Fase 2: nadie escribe sobre otro salvo administración ──────────────
  console.log('\nFase 2 — escritura sobre otros usuarios');

  await caso('el publicador NO puede editar el documento de otro', async () => {
    await assertFails(
      como(PUBLICADOR)
        .collection('usuarios')
        .doc(PENDIENTE)
        .update({ nombre: 'cambiado' })
    );
  });

  await caso('el publicador NO puede escribir el fcm_token de otro', async () => {
    await assertFails(
      como(PUBLICADOR)
        .collection('usuarios')
        .doc(PENDIENTE)
        .update({ fcm_token: 'robado' })
    );
  });

  await caso('el publicador NO puede borrar la cuenta de otro', async () => {
    await assertFails(
      como(PUBLICADOR).collection('usuarios').doc(PENDIENTE).delete()
    );
  });

  await caso('el publicador NO puede quitarse es_admin a sí mismo', async () => {
    // Se degrada primero al publicador con la sesión sin reglas: la regla de
    // `usuarios` compara contra `resource.data`, no contra el perfil, así que
    // con `es_admin: true` en el documento el update pasaría la comprobación
    // de claves. El caso real es que un publicador NUNCA llega a tenerlo.
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .collection('usuarios')
        .doc(PUBLICADOR)
        .update({ es_admin: true });
    });
    await assertFails(
      como(PUBLICADOR)
        .collection('usuarios')
        .doc(PUBLICADOR)
        .update({ es_admin: false })
    );
    await restaurar();
  });

  await caso('el admin NO puede quitarse su propio es_admin', async () => {
    await assertFails(
      como(ADMIN).collection('usuarios').doc(ADMIN).update({ es_admin: false })
    );
  });

  await caso('el admin SÍ aprueba a otro usuario', async () => {
    await assertSucceeds(
      como(ADMIN)
        .collection('usuarios')
        .doc(PENDIENTE)
        .update({ estado: 'aprobado' })
    );
    await restaurar();
  });

  await caso('el admin (no principal) NO reparte roles', async () => {
    await assertFails(
      como(ADMIN)
        .collection('usuarios')
        .doc(PUBLICADOR)
        .update({ es_admin_territorios: true })
    );
    await restaurar();
  });

  await caso('el admin (no principal) NO se cambia el rol a otro admin', async () => {
    await assertFails(
      como(ADMIN).collection('usuarios').doc(ADMIN).update({ es_admin: false })
    );
    await restaurar();
  });

  await caso('el admin principal SÍ da rol de territorios a otro', async () => {
    await assertSucceeds(
      como(PRINCIPAL, tokenPrincipal)
        .collection('usuarios')
        .doc(PUBLICADOR)
        .update({ es_admin_territorios: true })
    );
    await restaurar();
  });

  await caso('el admin SÍ borra la cuenta de otro', async () => {
    await assertSucceeds(
      como(ADMIN).collection('usuarios').doc(PENDIENTE).delete()
    );
    await restaurar();
  });

  // La migración usuarios/{uid} ya está hecha en producción: el id del
  // documento de usuario es el uid de Auth, así que estas dos se pueden
  // cerrar sin la deuda que las bloqueaba.

  await env.cleanup();

  console.log(`\n${pasadas} pasadas, ${fallos} fallidas`);
  process.exit(fallos === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
