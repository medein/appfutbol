import 'package:flutter/material.dart';

import '../main.dart';
import '../models/complejo_model.dart';
import '../services/api_service.dart';
import 'chat_screen.dart';
import 'home_screen.dart';
import 'mis_reservas_screen.dart';
import 'profile_screen.dart';

class MainShell extends StatefulWidget {
  final int pestanaInicial;
  final Complejo? complejo;
  final VoidCallback? onCambiarComplejo;

  const MainShell({
    super.key,
    this.pestanaInicial = 0,
    this.complejo,
    this.onCambiarComplejo,
  });

  @override
  State<MainShell> createState() => MainShellState();

  static void irA(BuildContext context, int indice) {
    context.findAncestorStateOfType<MainShellState>()?.cambiarPestana(indice);
  }
}

class MainShellState extends State<MainShell> {
  late int _indice;
  int _pendientesPorAprobar = 0;
  int _versionReservas = 0;
  int _versionComplejo = 0;
  Complejo? _complejo;

  @override
  void initState() {
    super.initState();
    _indice = widget.pestanaInicial;
    _complejo = widget.complejo;
    _contarPendientesAdmin();
  }

  @override
  void didUpdateWidget(covariant MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.complejo?.id != widget.complejo?.id) {
      setState(() {
        _complejo = widget.complejo;
        _versionComplejo++;
      });
    }
  }

  Future<void> _contarPendientesAdmin() async {
    if (!await ApiService.esAdmin()) return;
    final pendientes = await ApiService.getReservasPorAprobar();
    if (!mounted) return;
    setState(() => _pendientesPorAprobar = pendientes.length);
  }

  void cambiarPestana(int indice) {
    if (indice == _indice) return;
    setState(() => _indice = indice);
  }

  void reservaCreada({bool irAReservas = true}) {
    setState(() {
      _versionReservas++;
      if (irAReservas) _indice = 1;
    });
  }

  /// Se dispara cuando el usuario toca el botón 🔄 o el nombre del complejo.
  void _onCambiarComplejo() {
    debugPrint('🟡 [MainShell] _onCambiarComplejo invocado');
    debugPrint('🟡 [MainShell] callback disponible: ${widget.onCambiarComplejo != null}');

    if (widget.onCambiarComplejo != null) {
      widget.onCambiarComplejo!();
      return;
    }

    // Fallback: si no hay callback, hacer pop.
    debugPrint('🟡 [MainShell] Sin callback, haciendo pop');
    Navigator.maybePop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Reserva Tu Cancha',
              style: TextStyle(
                color: Color.fromARGB(255, 14, 159, 10),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            GestureDetector(
              onTap: _onCambiarComplejo,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.location_on_rounded,
                      size: 12, color: Colors.black54),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      _complejo?.nombre ?? 'Elegir complejo',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Icon(Icons.expand_more_rounded,
                      size: 14, color: Colors.black54),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Botón "Cambiar complejo" — SIEMPRE visible.
          IconButton(
            icon: const Icon(Icons.swap_horiz_rounded,
                color: Color.fromARGB(255, 14, 159, 10)),
            tooltip: 'Cambiar complejo',
            onPressed: _onCambiarComplejo,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded,
                color: Color.fromARGB(255, 14, 159, 10)),
            tooltip: 'Cerrar sesión',
            onPressed: () => cerrarSesionYSalir(context),
          ),
        ],
      ),
      body: IndexedStack(
        index: _indice,
        children: [
          HomeScreen(
            key: ValueKey('home_${_complejo?.id}_$_versionComplejo'),
            complejo: _complejo,
          ),
          MisReservasScreen(key: ValueKey('reservas_$_versionReservas')),
          const ChatScreen(),
          const PerfilScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: NavigationBar(
            selectedIndex: _indice,
            onDestinationSelected: (i) => setState(() => _indice = i),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.stadium_outlined),
                selectedIcon: Icon(Icons.stadium_rounded),
                label: 'Canchas',
              ),
              NavigationDestination(
                icon: _pendientesPorAprobar > 0
                    ? Badge(
                        label: Text('$_pendientesPorAprobar'),
                        child: const Icon(Icons.event_note_outlined),
                      )
                    : const Icon(Icons.event_note_outlined),
                selectedIcon: const Icon(Icons.event_note_rounded),
                label: 'Reservas',
              ),
              const NavigationDestination(
                icon: Icon(Icons.smart_toy_outlined),
                selectedIcon: Icon(Icons.smart_toy_rounded),
                label: 'Asistente',
              ),
              const NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Perfil',
              ),
            ],
          ),
        ),
      ),
    );
  }
}