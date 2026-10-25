import 'package:flutter/material.dart';

import '../models/reserva_model.dart';
import '../services/api_service.dart';
import '../services/notificacion_service.dart';
import '../theme/app_theme.dart';
import '../utils/formato.dart';
import '../widgets/app_widgets.dart';

/// Panel del administrador: valida los depósitos de las reservas pagadas
/// por transferencia y las aprueba o rechaza.
///
/// Las reservas pagadas con tarjeta no aparecen aquí porque se confirman
/// automáticamente al cobrarse.
class AdminReservasScreen extends StatefulWidget {
  const AdminReservasScreen({super.key});

  @override
  State<AdminReservasScreen> createState() => _AdminReservasScreenState();
}

class _AdminReservasScreenState extends State<AdminReservasScreen> {
  List<Reserva> _pendientes = [];
  bool _cargando = true;
  final Set<int> _procesando = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (mounted) setState(() => _cargando = true);
    final lista = await ApiService.getReservasPorAprobar();
    if (!mounted) return;
    setState(() {
      _pendientes = lista;
      _cargando = false;
    });
  }

  Future<void> _aprobar(Reserva reserva) async {
    setState(() => _procesando.add(reserva.id));

    final resultado = await ApiService.aprobarReserva(reserva.id);

    if (resultado.exito) {
      // Al quedar confirmada, ya se le puede programar el recordatorio.
      final confirmada = reserva.copyWith(estado: EstadoReserva.confirmada);
      await NotificacionService.programarRecordatorio(confirmada);
      await NotificacionService.avisarCambioEstado(confirmada);
    }

    if (!mounted) return;
    setState(() {
      _procesando.remove(reserva.id);
      if (resultado.exito) {
        _pendientes.removeWhere((r) => r.id == reserva.id);
      }
    });

    mostrarMensaje(
      context,
      resultado.exito
          ? 'Reserva #${reserva.id} confirmada'
          : resultado.mensaje ?? 'No se pudo aprobar',
      esExito: resultado.exito,
      esError: !resultado.exito,
    );
  }

  Future<void> _rechazar(Reserva reserva) async {
    final motivoCtrl = TextEditingController();

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rechazar el comprobante'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'El cliente recibirá una notificación con el motivo del rechazo '
              'para la reserva #${reserva.id}.',
              style: const TextStyle(fontSize: 14, color: AppColors.inkSoft),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: motivoCtrl,
              maxLength: 140,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Motivo del rechazo',
                hintText: 'Ej. El monto depositado no coincide',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: AppColors.inkSoft),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              minimumSize: const Size(0, 44),
            ),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _procesando.add(reserva.id));

    final motivo = motivoCtrl.text.trim().isEmpty
        ? 'Comprobante no válido'
        : motivoCtrl.text.trim();
    final resultado =
        await ApiService.rechazarReserva(reserva.id, motivo: motivo);

    if (resultado.exito) {
      await NotificacionService.cancelarRecordatorio(reserva.id);
      await NotificacionService.avisarCambioEstado(
        reserva.copyWith(
            estado: EstadoReserva.rechazada, motivoCancelacion: motivo),
      );
    }

    if (!mounted) return;
    setState(() {
      _procesando.remove(reserva.id);
      if (resultado.exito) {
        _pendientes.removeWhere((r) => r.id == reserva.id);
      }
    });

    mostrarMensaje(
      context,
      resultado.exito
          ? 'Reserva #${reserva.id} rechazada'
          : resultado.mensaje ?? 'No se pudo rechazar',
      esExito: resultado.exito,
      esError: !resultado.exito,
    );
  }

  void _verComprobante(Reserva reserva) {
    final url = ApiService.urlAbsoluta(reserva.comprobanteUrl);

    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Comprobante · Reserva #${reserva.id}',
                          style: const TextStyle(
                              fontSize: 15.5, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Debe coincidir con '
                          '${Formato.moneda(reserva.montoTotal)}',
                          style: const TextStyle(
                              fontSize: 12.5, color: AppColors.inkSoft),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: url == null
                  ? const Padding(
                      padding: EdgeInsets.all(34),
                      child: Column(
                        children: [
                          Icon(Icons.image_not_supported_outlined,
                              size: 40, color: AppColors.inkMuted),
                          SizedBox(height: 14),
                          Text(
                            'Esta reserva no tiene comprobante guardado en el '
                            'servidor.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 13.5, color: AppColors.inkSoft),
                          ),
                        ],
                      ),
                    )
                  : InteractiveViewer(
                      maxScale: 5,
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Padding(
                          padding: EdgeInsets.all(34),
                          child: Text(
                            'No pudimos cargar la imagen.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.inkMuted),
                          ),
                        ),
                        loadingBuilder: (_, child, progreso) => progreso == null
                            ? child
                            : const Padding(
                                padding: EdgeInsets.all(40),
                                child: Center(
                                  child: SizedBox(
                                    width: 26,
                                    height: 26,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.4),
                                  ),
                                ),
                              ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final totalPorCobrar =
        _pendientes.fold<double>(0, (suma, r) => suma + r.montoTotal);

    return Scaffold(
      body: Column(
        children: [
          GradientHeader(
            titulo: 'Aprobar reservas',
            subtitulo: 'Valida los depósitos por transferencia',
            mostrarAtras: true,
            paddingInferior: 24,
            acciones: [
              HeaderIconButton(
                icono: Icons.refresh_rounded,
                tooltip: 'Actualizar',
                onTap: _cargar,
              ),
            ],
            contenidoInferior: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(AppRadius.sm + 4),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _metrica('Por validar', '${_pendientes.length}'),
                  ),
                  Container(
                    width: 1,
                    height: 32,
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                  Expanded(
                    child: _metrica(
                        'Monto en revisión', Formato.moneda(totalPorCobrar)),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _cargando && _pendientes.isEmpty
                ? const Cargando(texto: 'Buscando depósitos por validar...')
                : RefreshIndicator(
                    onRefresh: _cargar,
                    color: AppColors.primary,
                    child: _pendientes.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: const [
                              SizedBox(height: 40),
                              EstadoVacio(
                                icono: Icons.task_alt_rounded,
                                titulo: 'Todo al día',
                                mensaje:
                                    'No hay depósitos pendientes de validación. '
                                    'Las reservas pagadas con tarjeta se '
                                    'confirman automáticamente.',
                              ),
                            ],
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                            itemCount: _pendientes.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, i) =>
                                _tarjetaPorAprobar(_pendientes[i]),
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _metrica(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            etiqueta,
            style: TextStyle(
                fontSize: 11.5, color: Colors.white.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valor,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaPorAprobar(Reserva reserva) {
    final ocupado = _procesando.contains(reserva.id);

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(height: 4, color: AppColors.warning.withValues(alpha: 0.85)),
          Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            reserva.canchaNombre,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Reserva #${reserva.id}',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.inkMuted),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      Formato.moneda(reserva.montoTotal),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryDark,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),
                FilaDato(
                  icono: Icons.person_outline_rounded,
                  etiqueta: 'Cliente',
                  valor: reserva.usuarioNombre ??
                      reserva.usuarioEmail ??
                      'Sin identificar',
                ),
                FilaDato(
                  icono: Icons.calendar_today_rounded,
                  etiqueta: 'Fecha y horario',
                  valor: '${Formato.desdeTexto(reserva.fecha)} · '
                      '${reserva.rangoHorario}',
                ),
                if (reserva.notas.trim().isNotEmpty)
                  FilaDato(
                    icono: Icons.edit_note_rounded,
                    etiqueta: 'Notas del cliente',
                    valor: reserva.notas,
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: ocupado ? null : () => _verComprobante(reserva),
                    icon: const Icon(Icons.receipt_long_rounded, size: 18),
                    label: const Text('Ver comprobante'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 46),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: ocupado ? null : () => _rechazar(reserva),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('Rechazar'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(
                              color: AppColors.danger, width: 1.4),
                          minimumSize: const Size(0, 48),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: ocupado ? null : () => _aprobar(reserva),
                        icon: ocupado
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check_rounded, size: 18),
                        label: Text(ocupado ? 'Espera...' : 'Aprobar'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
