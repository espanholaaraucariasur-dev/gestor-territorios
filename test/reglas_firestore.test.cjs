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

  await caso('el admin SÍ puede cambiar roles', async () => {
    await assertSucceeds(
      como(ADMIN)
        .collection('usuarios')
        .doc(PUBLICADOR)
        .update({ es_admin_territorios: true })
    );
    await restaurar();
  });

  // ── Notificaciones compartidas ─────────────────────────────────────────
  console.log('\nNotificaciones compartidas');

  await caso('el publicador NO puede borrar una notificación', async () => {
    await assertFails(
      como(PUBLICADOR).collection('notificaciones').doc('n1').delete()
    );
  });

  await caso('el publicador NO puede marcarla leída en el documento', async () => {
    await assertFails(
      como(PUBLICADOR).collection('notificaciones').doc('n1').update({
        leida: true,
      })
    );
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

  await caso('el publicador NO borra tarjetas', async () => {
    await assertFails(
      como(PUBLICADOR)
        .collection('territorios')
        .doc('t1')
        .collection('tarjetas')
        .doc('k1')
        .delete()
    );
  });

  await caso('el publicador NO crea territorios', async () => {
    await assertFails(
      como(PUBLICADOR).collection('territorios').doc('t2').set({ nombre: 'T2' })
    );
  });

  // ── Resto del ecosistema ───────────────────────────────────────────────
  console.log('\nResto del ecosistema');

  await caso('el publicador NO escribe estadísticas', async () => {
    await assertFails(
      como(PUBLICADOR).collection('estadisticas').doc('e1').update({ total: 99 })
    );
  });

  await caso('el publicador SÍ registra asistencia', async () => {
    await assertSucceeds(
      como(PUBLICADOR).collection('asistencia_historial').doc('a1').set({
        fecha: new Date(),
        total: 10,
      })
    );
  });

  await caso('el publicador NO toca configuración', async () => {
    await assertFails(
      como(PUBLICADOR).collection('configuracion').doc('codigo_acceso').set({
        codigo: 'x',
      })
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
  });

  await caso('el publicador NO puede ponerse es_admin_territorios', async () => {
    await assertFails(
      como(PUBLICADOR)
        .collection('usuarios')
        .doc(PUBLICADOR)
        .update({ es_admin_territorios: true })
    );
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

  await caso('un correo no verificado NO es admin principal', async () => {
    await assertFails(
      como('uid-falso', { email: 'angelrivas027@gmail.com', email_verified: false })
        .collection('notificaciones')
        .doc('n1')
        .delete()
    );
    await restaurar();
  });

  // PENDIENTE (ver REVISION-DEPURACION-SEGURIDAD-2026-11.md):
  //  - "el publicador NO puede editar el documento de otro"
  //  - "el admin NO puede quitarse su propio es_admin"
  // Hoy las dos pasan: mientras los documentos no tengan el uid de Auth como
  // id no hay forma de comprobar el rol sin leer el propio documento, y eso
  // desestabiliza la evaluación del emulador. Quedan como deuda declarada
  // hasta migrar el id del documento.

  await env.cleanup();

  console.log(`\n${pasadas} pasadas, ${fallos} fallidas`);
  process.exit(fallos === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
