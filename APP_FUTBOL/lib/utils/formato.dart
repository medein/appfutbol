import 'package:intl/intl.dart';

/// Formateo de fechas y montos en español, sin depender de la configuración
/// del sistema operativo.
class Formato {
  static const List<String> meses = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];

  static const List<String> mesesCortos = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];

  static const List<String> dias = [
    'lunes', 'martes', 'miércoles', 'jueves',
    'viernes', 'sábado', 'domingo',
  ];

  static const List<String> diasCortos = [
    'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom',
  ];

  /// "8 de septiembre de 2026"
  static String fechaLarga(DateTime? f) {
    if (f == null) return '—';
    return '${f.day} de ${meses[f.month - 1]} de ${f.year}';
  }

  /// "Martes 8 de septiembre"
  static String fechaConDia(DateTime? f) {
    if (f == null) return '—';
    final dia = dias[f.weekday - 1];
    final capitalizado = dia[0].toUpperCase() + dia.substring(1);
    return '$capitalizado ${f.day} de ${meses[f.month - 1]}';
  }

  /// "8 sep 2026"
  static String fechaCorta(DateTime? f) {
    if (f == null) return '—';
    return '${f.day} ${mesesCortos[f.month - 1]} ${f.year}';
  }

  /// "8 sep"
  static String diaMes(DateTime? f) {
    if (f == null) return '—';
    return '${f.day} ${mesesCortos[f.month - 1]}';
  }

  /// Formatea una fecha en texto "yyyy-MM-dd" a algo legible.
  static String desdeTexto(String iso, {bool conDia = true}) {
    final f = DateTime.tryParse(iso);
    if (f == null) return iso;
    return conDia ? fechaConDia(f) : fechaCorta(f);
  }

  /// "yyyy-MM-dd" para enviar al backend.
  static String iso(DateTime f) => DateFormat('yyyy-MM-dd').format(f);

  /// "14:30"
  static String hora(DateTime? f) {
    if (f == null) return '—';
    return '${f.hour.toString().padLeft(2, '0')}:'
        '${f.minute.toString().padLeft(2, '0')}';
  }

  /// "Q350.00"
  static String moneda(double monto) => 'Q${monto.toStringAsFixed(2)}';

  /// "1.5 h" o "2 h"
  static String duracion(double horas) {
    if (horas == horas.roundToDouble()) {
      return '${horas.toInt()} h';
    }
    return '${horas.toStringAsFixed(1)} h';
  }

  /// "Hoy", "Mañana" o la fecha corta.
  static String etiquetaDia(DateTime? f) {
    if (f == null) return '—';
    final hoy = DateTime.now();
    final soloF = DateTime(f.year, f.month, f.day);
    final soloHoy = DateTime(hoy.year, hoy.month, hoy.day);
    final dif = soloF.difference(soloHoy).inDays;
    if (dif == 0) return 'Hoy';
    if (dif == 1) return 'Mañana';
    if (dif == -1) return 'Ayer';
    return fechaConDia(f);
  }
}
