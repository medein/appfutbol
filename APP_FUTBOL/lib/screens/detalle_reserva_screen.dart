import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart'; // 👈 NUEVO IMPORT

import '../models/reserva_model.dart';
import '../services/api_service.dart';
import '../services/notificacion_service.dart';
import '../theme/app_theme.dart';
import '../utils/formato.dart';
import '../widgets/app_widgets.dart';

/// Detalle completo de una reserva: estado, línea de tiempo, datos del pago,
/// comprobante y acciones (cancelar, reenviar comprobante, recordatorio).
///
/// Devuelve `true` al cerrarse si algo cambió, para que la lista se recargue.
class DetalleReservaScreen extends StatefulWidget {
  final Reserva reserva;

  const DetalleReservaScreen({super.key, required this.reserva});

  @override
  State<DetalleReservaScreen> createState() => _DetalleReservaScreenState();
}

class _DetalleReservaScreenState extends State<DetalleReservaScreen> {
  late Reserva _reserva;
  bool _huboCambios = false;
  bool _procesando = false;
  bool _recordatorioActivo = false;

  @override
  void initState() {
    super.initState();
    _reserva = widget.reserva;
    _revisarRecordatorio();
  }

  Future<void> _revisarRecordatorio() async {
    final pendientes = await NotificacionService.pendientes();
    final activo = pendientes.any((n) =>
        n.id == _reserva.id * 10 + 1 || n.id == _reserva.id * 10 + 2);
    if (!mounted) return;
    setState(() => _recordatorioActivo = activo);
  }

  // ---------------------------------------------------------------------------
  // Acciones
  // ---------------------------------------------------------------------------

  Future<void> _alternarRecordatorio() async {
    if (_recordatorioActivo) {
      await NotificacionService.cancelarRecordatorio(_reserva.id);
      if (!mounted) return;
      setState(() => _recordatorioActivo = false);
      mostrarMensaje(context, 'Recordatorio desactivado');
    } else {
      await NotificacionService.pedirPermisos();
      await NotificacionService.programarRecordatorio(_reserva);
      await _revisarRecordatorio();
      if (!mounted) return;
      final horas = await NotificacionService.anticipacionHoras();
      if (!mounted) return;
      mostrarMensaje(
        context,
        _recordatorioActivo
            ? 'Te avisaremos $horas h antes (y el día anterior)'
            : 'No se pudo activar el recordatorio. Revisa los permisos de '
                'notificaciones.',
        esExito: _recordatorioActivo,
        esError: !_recordatorioActivo,
      );
    }
  }

  Future<void> _cancelar() async {
    final motivoCtrl = TextEditingController();

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cancelar esta reserva?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Esta acción no se puede deshacer.',
              style: TextStyle(fontSize: 14, color: AppColors.inkSoft),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: motivoCtrl,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Motivo (opcional)',
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

    setState(() => _procesando = true);
    final resultado =
        await ApiService.cancelarReserva(_reserva.id, motivoCtrl.text.trim());
    await NotificacionService.cancelarRecordatorio(_reserva.id);

    if (!mounted) return;
    setState(() {
      _procesando = false;
      if (resultado.exito) {
        _reserva = _reserva.copyWith(
          estado: EstadoReserva.cancelada,
          motivoCancelacion: motivoCtrl.text.trim().isEmpty
              ? 'Cancelado por el usuario'
              : motivoCtrl.text.trim(),
        );
        _huboCambios = true;
        _recordatorioActivo = false;
      }
    });

    mostrarMensaje(
      context,
      resultado.exito
          ? 'Reserva cancelada'
          : resultado.mensaje ?? 'No se pudo cancelar',
      esExito: resultado.exito,
      esError: !resultado.exito,
    );
  }

  Future<void> _reenviarComprobante() async {
    final origen = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 18),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppColors.primary),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded,
                  color: AppColors.primary),
              title: const Text('Tomar una foto'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (origen == null) return;

    final archivo =
        await ImagePicker().pickImage(source: origen, imageQuality: 80);
    if (archivo == null || !mounted) return;

    setState(() => _procesando = true);
    final resultado = await ApiService.subirComprobante(
      reservaId: _reserva.id,
      imagen: File(archivo.path),
    );

    if (!mounted) return;
    setState(() {
      _procesando = false;
      if (resultado.exito) {
        _reserva = _reserva.copyWith(
          comprobanteUrl: resultado.datos,
          estado: EstadoReserva.pendiente,
        );
        _huboCambios = true;
      }
    });

    mostrarMensaje(
      context,
      resultado.exito
          ? 'Comprobante enviado. Queda pendiente de aprobación.'
          : resultado.mensaje ?? 'No se pudo enviar el comprobante',
      esExito: resultado.exito,
      esError: !resultado.exito,
    );
  }

  // 👇 NUEVA ACCIÓN: Pagar con Recurrente
  Future<void> _pagarConRecurrente() async {
    setState(() => _procesando = true);

    // 1. Pedimos el link de pago a FastAPI
    final checkoutUrl = await ApiService.generarLinkPago(_reserva.id);

    if (checkoutUrl == null) {
      if (!mounted) return;
      setState(() => _procesando = false);
      mostrarMensaje(context, 'Error al conectar con la pasarela de pago. Intenta de nuevo.', esError: true);
      return;
    }

    // 2. Abrimos el navegador externo
    final uri = Uri.parse(checkoutUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      setState(() => _procesando = false);
      mostrarMensaje(context, 'No se pudo abrir el navegador para pagar', esError: true);
      return;
    }

    if (!mounted) return;
    setState(() => _procesando = false);
    
    mostrarMensaje(
      context, 
      'Redirigiendo al pago. Una vez completado, tu reserva se actualizará automáticamente.', 
      esExito: true,
      duracion: const Duration(seconds: 4),
    );
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final estado = _reserva.estadoEfectivo;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _huboCambios);
      },
      child: Scaffold(
        body: Column(
          children: [
            GradientHeader(
              titulo: _reserva.canchaNombre,
              subtitulo: _reserva.complejoNombre != null &&
                      _reserva.complejoNombre!.isNotEmpty
                  ? '${_reserva.complejoNombre} · Reserva #${_reserva.id}'
                  : 'Reserva #${_reserva.id}',
              mostrarAtras: true,
              onAtras: () => Navigator.pop(context, _huboCambios),
              paddingInferior: 26,
              contenidoInferior: _encabezadoEstado(estado),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
                children: [
                  // Línea de tiempo del estado
                  Text('Seguimiento',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 14),
                  AppCard(child: _lineaDeTiempo(estado)),

                  const SizedBox(height: 22),
                  Text('Detalles del partido',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 14),
                  AppCard(
                    child: Column(
                      children: [
                        if (_reserva.complejoNombre != null &&
                            _reserva.complejoNombre!.isNotEmpty)
                          FilaDato(
                            icono: Icons.location_on_rounded,
                            etiqueta: 'Complejo',
                            valor: _reserva.complejoNombre!,
                          ),
                        FilaDato(
                          icono: Icons.stadium_rounded,
                          etiqueta: 'Cancha',
                          valor: _reserva.canchaNombre,
                        ),
                        FilaDato(
                          icono: Icons.calendar_today_rounded,
                          etiqueta: 'Fecha',
                          valor: Formato.desdeTexto(_reserva.fecha),
                        ),
                        FilaDato(
                          icono: Icons.schedule_rounded,
                          etiqueta: 'Horario',
                          valor: '${_reserva.rangoHorario}  ·  '
                              '${Formato.duracion(_reserva.horasReservadas)}',
                        ),
                        if (_reserva.notas.trim().isNotEmpty)
                          FilaDato(
                            icono: Icons.edit_note_rounded,
                            etiqueta: 'Notas',
                            valor: _reserva.notas,
                          ),
                        if ((_reserva.motivoCancelacion ?? '').trim().isNotEmpty)
                          FilaDato(
                            icono: Icons.info_outline_rounded,
                            etiqueta: estado == EstadoReserva.rechazada
                                ? 'Motivo del rechazo'
                                : 'Motivo de cancelación',
                            valor: _reserva.motivoCancelacion!,
                            colorValor: AppColors.danger,
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),
                  Text('Pago', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 14),
                  AppCard(
                    child: Column(
                      children: [
                        FilaDato(
                          icono: _reserva.metodoPago.icono,
                          etiqueta: 'Método de pago',
                          valor: _reserva.metodoPago.etiqueta,
                        ),
                        FilaDato(
                          icono: Icons.payments_rounded,
                          etiqueta: 'Total',
                          valor: Formato.moneda(_reserva.montoTotal),
                          colorValor: AppColors.primaryDark,
                        ),
                        FilaDato(
                          icono: Icons.receipt_rounded,
                          etiqueta: 'Situación del pago',
                          valor: _textoSituacionPago(estado),
                          colorValor: estado.color,
                        ),
                        if (_reserva.fechaCreacion != null)
                          FilaDato(
                            icono: Icons.history_rounded,
                            etiqueta: 'Reservada el',
                            valor:
                                '${Formato.fechaCorta(_reserva.fechaCreacion)} '
                                'a las ${Formato.hora(_reserva.fechaCreacion)}',
                          ),
                      ],
                    ),
                  ),

                  // Comprobante (Solo si es transferencia)
                  if (_reserva.metodoPago == MetodoPago.transferencia) ...[
                    const SizedBox(height: 22),
                    Text('Comprobante',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 14),
                    _bloqueComprobante(),
                  ],

                  // Recordatorio
                  if (_reserva.admiteRecordatorio) ...[
                    const SizedBox(height: 22),
                    Text('Recordatorio',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 14),
                    AppCard(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: (_recordatorioActivo
                                      ? AppColors.primary
                                      : AppColors.inkMuted)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Icon(
                              _recordatorioActivo
                                  ? Icons.notifications_active_rounded
                                  : Icons.notifications_off_rounded,
                              size: 20,
                              color: _recordatorioActivo
                                  ? AppColors.primary
                                  : AppColors.inkMuted,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _recordatorioActivo
                                      ? 'Recordatorio activo'
                                      : 'Recordatorio desactivado',
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.ink,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _recordatorioActivo
                                      ? 'Te avisaremos el día anterior y unas '
                                          'horas antes del partido.'
                                      : 'Actívalo para no olvidar tu partido.',
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      color: AppColors.inkSoft,
                                      height: 1.35),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _recordatorioActivo,
                            activeThumbColor: AppColors.primary,
                            onChanged: (_) => _alternarRecordatorio(),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // 👇 NUEVA ACCIÓN: Botón para pagar con tarjeta (Recurrente)
                  if (_reserva.estadoEfectivo == EstadoReserva.pendiente) ...[
                    const SizedBox(height: 26),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _procesando ? null : _pagarConRecurrente,
                        icon: const Icon(Icons.credit_card_rounded, size: 19),
                        label: const Text('PAGAR CON TARJETA (RECURRENTE)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],

                  // Acciones
                  if (_reserva.sePuedeCancelar) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _procesando ? null : _cancelar,
                        icon: const Icon(Icons.close_rounded, size: 19),
                        label: const Text('Cancelar reserva'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(
                              color: AppColors.danger, width: 1.4),
                        ),
                      ),
                    ),
                  ],
                  if (_procesando) ...[
                    const SizedBox(height: 18),
                    const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _encabezadoEstado(EstadoReserva estado) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.sm + 4),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
            child: Icon(estado.icono, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  estado.etiqueta,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  estado.descripcion,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineaDeTiempo(EstadoReserva estado) {
    final esTransferencia = _reserva.metodoPago == MetodoPago.transferencia;

    final pasos = <_Paso>[
      _Paso(
        titulo: 'Reserva creada',
        detalle: _reserva.fechaCreacion != null
            ? '${Formato.fechaCorta(_reserva.fechaCreacion)} · '
                '${Formato.hora(_reserva.fechaCreacion)}'
            : 'Solicitud registrada',
        completado: true,
      ),
      if (esTransferencia)
        _Paso(
          titulo: 'Comprobante enviado',
          detalle: 'Depósito por ${Formato.moneda(_reserva.montoTotal)}',
          completado: true,
        )
      else
        _Paso(
          titulo: 'Pago con tarjeta aprobado',
          detalle: '${Formato.moneda(_reserva.montoTotal)} cobrados',
          completado: estado != EstadoReserva.pendiente, // Se completa al pagar
        ),
      _Paso(
        titulo: esTransferencia
            ? 'Validación del administrador'
            : 'Reserva confirmada',
        detalle: estado == EstadoReserva.pendiente
            ? 'En proceso...'
            : estado == EstadoReserva.rechazada
                ? 'Comprobante rechazado'
                : estado == EstadoReserva.cancelada
                    ? 'Se canceló antes de jugarse'
                    : 'Cancha apartada',
        completado: estado == EstadoReserva.confirmada ||
            estado == EstadoReserva.completada,
        fallido: estado == EstadoReserva.rechazada ||
            estado == EstadoReserva.cancelada,
        enProceso: estado == EstadoReserva.pendiente,
      ),
      _Paso(
        titulo: 'Partido jugado',
        detalle: estado == EstadoReserva.completada
            ? '¡Gracias por jugar con nosotros!'
            : '${Formato.etiquetaDia(_reserva.inicio)} · '
                '${_reserva.rangoHorario}',
        completado: estado == EstadoReserva.completada,
        fallido: estado == EstadoReserva.cancelada ||
            estado == EstadoReserva.rechazada,
      ),
    ];

    return Column(
      children: [
        for (int i = 0; i < pasos.length; i++)
          _filaPaso(pasos[i], esUltimo: i == pasos.length - 1),
      ],
    );
  }

  Widget _filaPaso(_Paso paso, {required bool esUltimo}) {
    final color = paso.fallido
        ? AppColors.danger
        : paso.enProceso
            ? AppColors.warning
            : paso.completado
                ? AppColors.primary
                : AppColors.inkMuted;

    final icono = paso.fallido
        ? Icons.close_rounded
        : paso.enProceso
            ? Icons.more_horiz_rounded
            : paso.completado
                ? Icons.check_rounded
                : Icons.circle_outlined;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: (paso.completado || paso.enProceso || paso.fallido)
                    ? color
                    : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 1.8),
              ),
              child: Icon(
                icono,
                size: 15,
                color: (paso.completado || paso.enProceso || paso.fallido)
                    ? Colors.white
                    : color,
              ),
            ),
            if (!esUltimo)
              Container(
                width: 2,
                height: 34,
                color: paso.completado
                    ? AppColors.primary.withValues(alpha: 0.35)
                    : AppColors.border,
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: esUltimo ? 0 : 14, top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  paso.titulo,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: paso.completado || paso.enProceso || paso.fallido
                        ? AppColors.ink
                        : AppColors.inkMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  paso.detalle,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: paso.enProceso || paso.fallido
                        ? color
                        : AppColors.inkSoft,
                    fontWeight: paso.enProceso || paso.fallido
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _bloqueComprobante() {
    final url = ApiService.urlAbsoluta(_reserva.comprobanteUrl);

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (url != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm + 2),
              child: Image.network(
                url,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 120,
                  color: AppColors.background,
                  child: const Center(
                    child: Text(
                      'No pudimos cargar la imagen del comprobante',
                      style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                    ),
                  ),
                ),
                loadingBuilder: (_, child, progreso) => progreso == null
                    ? child
                    : Container(
                        height: 120,
                        color: AppColors.background,
                        child: const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          ),
                        ),
                      ),
              ),
            )
          else
            Container(
              height: 90,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(AppRadius.sm + 2),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.image_not_supported_outlined,
                        color: AppColors.inkMuted, size: 24),
                    SizedBox(height: 6),
                    Text(
                      'Sin comprobante guardado en el servidor',
                      style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (_reserva.estadoEfectivo == EstadoReserva.pendiente ||
              _reserva.estadoEfectivo == EstadoReserva.rechazada)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _procesando ? null : _reenviarComprobante,
                icon: const Icon(Icons.upload_rounded, size: 18),
                label: Text(url == null
                    ? 'Subir comprobante'
                    : 'Reenviar comprobante'),
              ),
            ),
        ],
      ),
    );
  }

  String _textoSituacionPago(EstadoReserva estado) {
    if (_reserva.metodoPago == MetodoPago.tarjeta) {
      return estado == EstadoReserva.cancelada
          ? 'Pagado (cancelado después)'
          : 'Pagado en su totalidad';
    }
    switch (estado) {
      case EstadoReserva.pendiente:
        return 'Depósito por verificar';
      case EstadoReserva.confirmada:
      case EstadoReserva.completada:
        return 'Depósito verificado';
      case EstadoReserva.rechazada:
        return 'Depósito no verificado';
      case EstadoReserva.cancelada:
        return 'Reserva cancelada';
    }
  }
}

class _Paso {
  final String titulo;
  final String detalle;
  final bool completado;
  final bool fallido;
  final bool enProceso;

  _Paso({
    required this.titulo,
    required this.detalle,
    this.completado = false,
    this.fallido = false,
    this.enProceso = false,
  });
}