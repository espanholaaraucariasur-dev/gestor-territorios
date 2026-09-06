// Normalización compartida de direcciones.
// IMPORTANTE: usar SIEMPRE esta función al escribir y al buscar
// 'direccion_normalizada' en Firestore, para que ambos lados coincidan.

const Map<String, String> _acentos = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ç': 'c', 'ñ': 'n',
};

/// Quita acentos reemplazando cada vocal acentuada por su base
/// (á → a), NO por espacio. Evita el bug "Araucária" → "arauc ria".
String quitarAcentos(String t) {
  final buf = StringBuffer();
  for (final r in t.runes) {
    final ch = String.fromCharCode(r);
    buf.write(_acentos[ch] ?? ch);
  }
  return buf.toString();
}

String _expandirAbreviaturas(String t) {
  final Map<String, String> abrev = {
    r'^\br\.?\b': 'rua',
    r'^\bru\b': 'rua',
    r'^\bav\.?\b': 'avenida',
    r'^\bgave\b': 'avenida',
    r'^\btrv?\.?\b': 'travessa',
    r'^\btrav\b': 'travessa',
    r'^\bpc\.?\b': 'praca',
    r'^\bpca\b': 'praca',
    r'^\bal\.?\b': 'alameda',
    r'^\brod\.?\b': 'rodovia',
    r'^\bbr\b': 'rodovia',
    r'^\bvq\b': 'vila',
    r'^\bcond\.?\b': 'condominio',
    r'^\bres\b': 'residencial',
    r'^\bpd\b': 'prolongamento',
    r'^\bprol\b': 'prolongamento',
    r'^\blm\b': 'loteamento',
    r'^\blot\b': 'loteamento',
    r'^\bqd\b': 'quadra',
    r'^\bq\b': 'quadra',
    r'^\bch\b': 'chacara',
    r'^\best\b': 'estrada',
    r'^\brdo\b': 'rodovia',
  };
  for (final entry in abrev.entries) {
    t = t.replaceAll(RegExp(entry.key), entry.value);
  }
  return t;
}

/// Normalización robusta: minúsculas, sin CEP, sin "nº",
/// abreviaturas expandidas, SIN acentos y solo [a-z0-9 ].
/// Ej: "R. Araucária, 1667" → "rua araucaria 1667"
String normalizarDireccion(String s) {
  if (s.isEmpty) return '';
  var t = s.toLowerCase();
  t = t.replaceAll(RegExp(r'cep[:\s]*\d{4,10}'), ' ');
  t = t.replaceAll(RegExp(r'\b\d{5}-?\d{3}\b'), ' ');
  t = t.replaceAll(RegExp(r'\b(n\.?|no\.?|nº|n°)\b'), ' ');
  t = quitarAcentos(t); // ← antes de limpiar caracteres raros
  t = _expandirAbreviaturas(t);
  t = t.replaceAll('apto', 'apartamento');
  t = t.replaceAll('apt', 'apartamento');
  t = t.replaceAll('dpto', 'departamento');
  t = t.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t;
}
