import 'package:flutter/material.dart';

import '../models/reserva_model.dart';
import '../services/api_service.dart';
import '../services/notificacion_service.dart';
import '../services/reserva_store.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/reserva_card.dart';
import 'detalle_reserva_screen.dart';
import 'main_shell.dart';

/// Mis reservas, separadas en tres pestañas:
///  * **Próximas**   – confirmadas que aún no se juegan
///  * **Pendientes** – esperando que el administrador valide el depósito
///  * **Historial**  – completadas, canceladas y rechazadas
class MisReservasScreen extends StatefulWidget {
  const MisReservasScreen({super.key});

  @override
  State<MisReservasScreen> createState() => _MisReservasScreenState();
}

class _MisReservasScreenState extends State<MisReservasScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<Reserva> _todas = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _cargar();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _cargar({bool avisarCambios = true}) async {
    if (mounted) setState(() => _cargando = true);

    final reservas = await ApiService.getTodasMisReservas();

    // Si el administrador aprobó o rechazó algo desde la última vez que
    // abrimos la app, se lo notificamos al usuario.
    if (avisarCambios) {
      final cambiadas = await ReservaStore.detectarCambiosDeEstado(reservas);
      for (final r in cambiadas) {
        await NotificacionService.avisarCambioEstado(r);
      }
    }

    // Y reprogramamos los recordatorios con la información más reciente.
    await NotificacionService.sincronizarRecordatorios(reservas);

    if (!mounted) return;
    setState(() {
      _todas = reservas;
      _cargando = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Filtros
  // ---------------------------------------------------------------------------

  List<Reserva> get _proximas {
    final lista = _todas
        .where((r) =>
            r.estadoEfectivo == EstadoReserva.confirmada && !r.yaPaso)
        .toList()
      ..sort(_porFechaAscendente);
    return lista;
  }

  List<Reserva> get _pendientes {
    final lista = _todas.where((r) => r.esperandoAprobacion).toList()
      ..sort(_porFechaAscendente);
    return lista;
  }

  List<Reserva> get _historial {
    final lista = _todas.where((r) => r.estadoEfectivo.esCerrado).toList()
      ..sort(_porFechaDescendente);
    return lista;
  }

  int _porFechaAscendente(Reserva a, Reserva b) {
    final ai = a.inicio, bi = b.inicio;
    if (ai == null || bi == null) return 0;
    return ai.compareTo(bi);
  }

  int _porFechaDescendente(Reserva a, Reserva b) => _porFechaAscendente(b, a);

  // ---------------------------------------------------------------------------
  // Acciones
  // ---------------------------------------------------------------------------

  Future<void> _confirmarCancelacion(Reserva reserva) async {
    final motivoCtrl = TextEditingController();

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cancelar esta reserva?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Se cancelará tu reserva en ${reserva.canchaNombre} del '
              '${reserva.fecha} (${reserva.rangoHorario}).',
              style: const TextStyle(fontSize: 14, color: AppColors.inkSoft),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: motivoCtrl,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Motivo (opcional)',
                hintText: 'Ej. Se canceló el partido',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: AppColors.inkSoft),
            child: const Text('No, mantener'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              minimumSize: const Size(0, 44),
            ),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    final resultado =
        await ApiService.cancelarReserva(reserva.id, motivoCtrl.text.trim());

    // Al cancelar ya no tiene sentido recordarle el partido.
    await NotificacionService.cancelarRecordatorio(reserva.id);

    if (!mounted) return;

    mostrarMensaje(
      context,
      resultado.exito
          ? 'Reserva cancelada'
          : resultado.mensaje ?? 'No se pudo cancelar la reserva',
      esError: !resultado.exito,
      esExito: resultado.exito,
    );

    if (resultado.exito) await _cargar(avisarCambios: false);
  }

  Future<void> _abrirDetalle(Reserva reserva) async {
    final cambio = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => DetalleReservaScreen(reserva: reserva)),
    );
    if (cambio == true && mounted) await _cargar(avisarCambios: false);
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: AppColors.heroGradient,
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(AppRadius.lg + 6),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Mis reservas',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Tu historial y lo que viene',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 13.5),
                              ),
                            ],
                          ),
                        ),
                        HeaderIconButton(
                          icono: Icons.refresh_rounded,
                          tooltip: 'Actualizar',
                          onTap: () => _cargar(avisarCambios: false),
                        ),
                      ],
                    ),
                  ),
                  TabBar(
                    controller: _tabController,
                    isScrollable: false,
                    tabs: [
                      _tab('Próximas', _proximas.length),
                      _tab('Pendientes', _pendientes.length),
                      _tab('Historial', _historial.length),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _cargando && _todas.isEmpty
                ? const Cargando(texto: 'Cargando tus reservas...')
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _lista(
                        _proximas,
                        vacioIcono: Icons.event_available_rounded,
                        vacioTitulo: 'No tienes reservas próximas',
                        vacioMensaje:
                            'Cuando reserves y tu pago quede confirmado, tu '
                            'partido aparecerá aquí con su recordatorio.',
                        vacioAccion: 'Reservar una cancha',
                        permitirCancelar: true,
                      ),
                      _lista(
                        _pendientes,
                        vacioIcono: Icons.hourglass_empty_rounded,
                        vacioTitulo: 'Nada pendiente por ahora',
                        vacioMensaje:
                            'Aquí verás las reservas pagadas por transferencia '
                            'mientras el administrador valida tu depósito.',
                        permitirCancelar: true,
                        encabezado: const Aviso(
                          texto: 'Estas reservas ya están apartadas, pero se '
                              'confirman cuando el administrador verifique el '
                              'depósito. Te avisaremos con una notificación.',
                          icono: Icons.hourglass_top_rounded,
                          color: AppColors.warning,
                        ),
                      ),
                      _lista(
                        _historial,
                        vacioIcono: Icons.history_rounded,
                        vacioTitulo: 'Tu historial está vacío',
                        vacioMensaje:
                            'Aquí se guardan todas tus reservas jugadas, '
                            'canceladas y rechazadas.',
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tab(String texto, int cantidad) {
    return Tab(
      height: 52,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(texto, overflow: TextOverflow.ellipsis),
          ),
          if (cantidad > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              constraints: const BoxConstraints(minWidth: 20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                '$cantidad',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _lista(
    List<Reserva> reservas, {
    required IconData vacioIcono,
    required String vacioTitulo,
    required String vacioMensaje,
    String? vacioAccion,
    bool permitirCancelar = false,
    Widget? encabezado,
  }) {
    return RefreshIndicator(
      onRefresh: () => _cargar(avisarCambios: false),
      color: AppColors.primary,
      child: reservas.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.06),
                EstadoVacio(
                  icono: vacioIcono,
                  titulo: vacioTitulo,
                  mensaje: vacioMensaje,
                  accionTexto: vacioAccion,
                  onAccion: vacioAccion == null
                      ? null
                      : () => MainShell.irA(context, 0),
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              itemCount: reservas.length + (encabezado != null ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                if (encabezado != null) {
                  if (i == 0) return encabezado;
                  i -= 1;
                }
                final reserva = reservas[i];
                return ReservaCard(
                  reserva: reserva,
                  onTap: () => _abrirDetalle(reserva),
                  onCancelar: permitirCancelar
                      ? () => _confirmarCancelacion(reserva)
                      : null,
                );
              },
            ),
    );
  }
}
