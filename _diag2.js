const { initializeApp, cert } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const serviceAccount = require("./serviceAccountKey.json");
const app = initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore(app);

async function run() {
  // 1. Usuarios y sus flags de admin
  const us = await db.collection("usuarios").get();
  console.log("=== USUARIOS (es_admin / es_admin_territorios / es_conductor) ===");
  for (const doc of us.docs) {
    const d = doc.data();
    console.log(`"${d.nombre || d.displayName || '?'}" | admin:${d.es_admin} | adminTer:${d.es_admin_territorios} | conductor:${d.es_conductor} | estado:${d.estado} | uid:${d.uid || '?'}`);
  }

  // 2. Documento de visibilidad
  const vis = await db.collection("configuracion").doc("ecosistema2_visibilidad").get();
  console.log("\n=== ecosistema2_visibilidad ===");
  if (vis.exists) {
    const d = vis.data() || {};
    const ids = d.usuario_ids || [];
    console.log("usuario_ids count:", ids.length);
    // Mostrar los nombres si podemos resolver
    const usMap = {};
    for (const doc of us.docs) usMap[doc.data().uid] = doc.data().nombre || doc.data().displayName;
    for (const id of ids) console.log("  liberado uid:", id, "->", usMap[id] || "(sin nombre)");
  } else {
    console.log("NO EXISTE el documento");
  }

  // 3. Buscar "campo mantenimiento" en configuracion/territorios
  console.log("\n=== configuracion (docs) ===");
  const cfg = await db.collection("configuracion").get();
  for (const doc of cfg.docs) {
    const d = doc.data();
    console.log(`  configuracion/${doc.id}:`, JSON.stringify(d).substring(0, 200));
  }
}

run().catch((e) => { console.error("ERROR:", e); process.exit(1); });
