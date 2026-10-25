import 'package:flutter/material.dart';

import '../models/complejo_model.dart';
import '../services/api_service.dart';
import 'complejos_screen.dart';
import 'main_shell.dart';

/// Pantalla intermedia entre el login y la app principal.
class SeleccionComplejoScreen extends StatefulWidget {
  const SeleccionComplejoScreen({super.key});

  @override
  State<SeleccionComplejoScreen> createState() =>
      _SeleccionComplejoScreenState();
}

class _SeleccionComplejoScreenState extends State<SeleccionComplejoScreen> {
  Complejo? _complejo;

  @override
  void initState() {
    super.initState();
    // Siempre arrancamos mostrando el selector.
    ApiService.olvidarComplejo();
  }

  /// Vuelve al selector: se llama cuando el usuario toca el botón 🔄
  /// en el AppBar del MainShell.
  Future<void> _cambiarComplejo() async {
    debugPrint('🔵 [_SeleccionComplejo] Cambiar complejo solicitado');

    await ApiService.olvidarComplejo();

    if (!mounted) {
      debugPrint('🔴 [_SeleccionComplejo] Widget no montado, cancelando');
      return;
    }

    debugPrint('🟢 [_SeleccionComplejo] Complejo limpiado, volviendo al selector');
    setState(() => _complejo = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_complejo == null) {
      return ComplejosScreen(
        onSeleccionar: (complejo) {
          debugPrint('🟢 [_SeleccionComplejo] Complejo elegido: ${complejo.nombre}');
          setState(() => _complejo = complejo);
        },
      );
    }

    return MainShell(
      complejo: _complejo,
      onCambiarComplejo: _cambiarComplejo,
    );
  }
}