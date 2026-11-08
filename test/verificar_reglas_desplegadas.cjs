// Verifica que las reglas desplegadas en producción siguen siendo las que
// probamos en el emulador. Comprueba el ÚNICO efecto observable sin
// credenciales de la app: que sin sesión no se pueda leer el directorio.
//
//   node test/verificar_reglas_desplegadas.cjs
//
//  - Un GET sin auth debe devolver PERMISSION_DENIED (antes devolvía
//    "Missing or insufficient permissions" igual, así que el chequeo real es
//    que NO devuelva datos ni un error distinto).
//  - Si devuelve 200 con datos, las reglas viejas siguen activas.

const PROYECTO = 'territorio-sur-8b72c';
const API_KEY = 'AIzaSyCFOTnGAwj9F8A9DB45jfUZet5_LHwMocM';
const URL =
  `https://firestore.googleapis.com/v1/projects/${PROYECTO}` +
  `/databases/(default)/documents/usuarios?key=${API_KEY}&pageSize=1`;

(async () => {
  const res = await fetch(URL);
  const texto = await res.text();
  let cuerpo = {};
  try {
    cuerpo = JSON.parse(texto);
  } catch (_) {}

  if (res.status === 200 && Array.isArray(cuerpo.documents)) {
    console.log('❌ Las reglas viejas siguen activas: el directorio es legible sin sesión.');
    process.exit(1);
  }
  if (cuerpo.error && cuerpo.error.status === 'PERMISSION_DENIED') {
    console.log('✅ Reglas desplegadas: sin sesión el directorio responde PERMISSION_DENIED.');
    process.exit(0);
  }
  console.log(`⚠️  Respuesta inesperada (${res.status}): ${texto.slice(0, 200)}`);
  process.exit(2);
})();
