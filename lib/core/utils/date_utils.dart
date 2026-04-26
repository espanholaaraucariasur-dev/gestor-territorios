class AppDateUtils {
  static String mesActual() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  static String formatearRelativo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inSeconds < 60) return 'unos segundos';
    if (diff.inMinutes < 60) return '${diff.inMinutes} minutos';
    if (diff.inHours < 24) return '${diff.inHours} horas';
    if (diff.inDays < 7) return '${diff.inDays} días';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} semanas';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} meses';
    return '${(diff.inDays / 365).floor()} años';
  }

  static String formatearFecha(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year}';

  static String formatearFechaHora(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year} '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}
