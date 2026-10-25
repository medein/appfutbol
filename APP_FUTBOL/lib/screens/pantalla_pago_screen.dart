import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart'; // 👈 IMPORTANTE

import '../models/cancha_model.dart';
import '../models/reserva_model.dart';
import '../services/api_service.dart';
import '../services/notificacion_service.dart';
import '../theme/app_theme.dart';
import '../utils/formato.dart';
import '../widgets/app_widgets.dart';
import 'package:flutter/services.dart'; // 👈 Agrega esta línea

/// Pantalla de pago.
///
/// * **Tarjeta**: Redirige a la pasarela segura de Recurrente (navegador).
/// * **Transferencia**: se sube el comprobante y la reserva queda PENDIENTE
///   hasta que el administrador valide el depósito.
class PantallaPagoScreen extends StatefulWidget {
  final Cancha cancha;
  final String fecha; // yyyy-MM-dd
  final String horaInicio; // HH:mm
  final String horaFin; // HH:mm
  final double montoTotal;

  const PantallaPagoScreen({
    super.key,
    required this.cancha,
    required this.fecha,
    required this.horaInicio,
    required this.horaFin,
    required this.montoTotal,
  });

  @override
  State<PantallaPagoScreen> createState() => _PantallaPagoScreenState();
}

class _PantallaPagoScreenState extends State<PantallaPagoScreen> {
  MetodoPago _metodo = MetodoPago.tarjeta;
  bool _procesando = false;

  // Comprobante de transferencia
  File? _comprobante;
  final ImagePicker _picker = ImagePicker();

  // Solo queda el controlador de notas
  final _notasCtrl = TextEditingController();

  @override
  void dispose() {
    _notasCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Comprobante (Transferencia)
  // ---------------------------------------------------------------------------

  Future<void> _elegirComprobante(ImageSource origen) async {
    try {
      final archivo = await _picker.pickImage(source: origen, imageQuality: 80);
      if (archivo != null) {
        setState(() => _comprobante = File(archivo.path));
      }
    } catch (e) {
      if (mounted) {
        mostrarMensaje(context, 'No pudimos abrir la cámara o la galería',
            esError: true);
      }
    }
  }

  void _menuComprobante() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 18),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppColors.primary),
              title: const Text('Elegir de la galería'),
              onTap: () {
                Navigator.pop(ctx);
                _elegirComprobante(ImageSource.gallery);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_camera_rounded, color: AppColors.primary),
              title: const Text('Tomar una foto'),
              onTap: () {
                Navigator.pop(ctx);
                _elegirComprobante(ImageSource.camera);
              },
            ),
            if (_comprobante != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: AppColors.danger),
                title: const Text('Quitar la foto',
                    style: TextStyle(color: AppColors.danger)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _comprobante = null);
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Confirmar Pago
  // ---------------------------------------------------------------------------

  Future<void> _confirmar() async {
    // 1. Validaciones
    if (_metodo == MetodoPago.transferencia) {
      if (_comprobante == null) {
        mostrarMensaje(
          context,
          'Adjunta la foto de tu comprobante de depósito',
          esError: true,
        );
        return;
      }
    }

    setState(() => _procesando = true);

    // 2. Crear la reserva.
    final resultado = await ApiService.crearReserva(
      canchaId: widget.cancha.id,
      canchaNombre: widget.cancha.nombre,
      fecha: widget.fecha,
      horaInicio: widget.horaInicio,
      horaFin: widget.horaFin,
      montoTotal: widget.montoTotal,
      metodoPago: _metodo,
      notas: _notasCtrl.text.trim(),
    );

    if (!resultado.exito || resultado.datos == null) {
      if (!mounted) return;
      setState(() => _procesando = false);
      mostrarMensaje(context, resultado.mensaje ?? 'No se pudo crear la reserva',
          esError: true);
      return;
    }

    var reserva = resultado.datos!;

    // 3. Completar el pago según el método elegido.
    if (_metodo == MetodoPago.transferencia) {
      // --- FLUJO DE TRANSFERENCIA ---
      final subida = await ApiService.subirComprobante(
        reservaId: reserva.id,
        imagen: _comprobante!,
      );
      if (!subida.exito && mounted) {
        mostrarMensaje(
          context,
          '${subida.mensaje} La reserva quedó registrada; puedes reenviar el '
          'comprobante desde el detalle.',
          esError: true,
          duracion: const Duration(seconds: 5),
        );
      }
      reserva = reserva.copyWith(comprobanteUrl: subida.datos);

      await NotificacionService.programarRecordatorio(reserva);
      await NotificacionService.avisarCambioEstado(reserva);

      if (!mounted) return;
      setState(() => _procesando = false);
      await _mostrarExito(reserva);

    } else if (_metodo == MetodoPago.tarjeta) {
      // --- FLUJO DE TARJETA CON RECURRENTE ---
      
      // Pedimos el link de pago a FastAPI
      final checkoutUrl = await ApiService.generarLinkPago(reserva.id);

      if (checkoutUrl == null) {
        if (!mounted) return;
        setState(() => _procesando = false);
        mostrarMensaje(context, 'Error al conectar con la pasarela de pago. Intenta de nuevo.', esError: true);
        return;
      }

      // Abrimos el navegador externo
            // Abrimos el navegador externo o interno
      final uri = Uri.parse(checkoutUrl);
      
      if (await canLaunchUrl(uri)) {
        // 1. Intentamos abrir en navegador externo (Chrome/Safari)
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(uri)) {
        // 2. Si falla, intentamos abrir en una vista web interna de la app
        await launchUrl(uri, mode: LaunchMode.inAppWebView);
      } else {
        // 3. Si todo falla, mostramos el error
        if (!mounted) return;
        setState(() => _procesando = false);
        mostrarMensaje(context, 'No se pudo abrir el navegador para pagar', esError: true);
        return;
      }

      if (!mounted) return;
      setState(() => _procesando = false);
      
      // Mostramos el diálogo explicando la redirección
      await _mostrarRedireccionPago(reserva);
    }
  }

  // Diálogo para Transferencia
  Future<void> _mostrarExito(Reserva reserva) async {
    final confirmada = reserva.estado == EstadoReserva.confirmada;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: (confirmada ? AppColors.primary : AppColors.warning)
                      .withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  confirmada
                      ? Icons.check_circle_rounded
                      : Icons.hourglass_top_rounded,
                  size: 46,
                  color: confirmada ? AppColors.primary : AppColors.warning,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                confirmada ? '¡Reserva confirmada!' : '¡Comprobante enviado!',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                confirmada
                    ? 'Pagaste ${Formato.moneda(widget.montoTotal)}. Tu cancha ya está apartada.'
                    : 'Tu reserva quedó en estado PENDIENTE. El administrador validará tu depósito y te avisaremos.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.inkSoft, height: 1.5),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                ),
                child: Column(
                  children: [
                    _filaResumenDialogo('Cancha', widget.cancha.nombre),
                    _filaResumenDialogo('Fecha', Formato.desdeTexto(widget.fecha)),
                    _filaResumenDialogo('Horario', '${widget.horaInicio} - ${widget.horaFin}'),
                    _filaResumenDialogo('Estado', reserva.estado.etiqueta, color: reserva.estado.color),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('VER MIS RESERVAS'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (mounted) Navigator.pop(context, reserva);
  }

  // Diálogo para Tarjeta (Redirección a Recurrente)
  Future<void> _mostrarRedireccionPago(Reserva reserva) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.open_in_browser_rounded, size: 46, color: AppColors.primary),
              ),
              const SizedBox(height: 20),
              const Text(
                'Redirigiendo al pago',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.ink),
              ),
              const SizedBox(height: 10),
              const Text(
                'Te hemos enviado al navegador para que pagues de forma segura con Recurrente. Una vez completado el pago, tu reserva se confirmará automáticamente en un par de segundos.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.inkSoft, height: 1.5),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('ENTENDIDO'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (mounted) Navigator.pop(context, reserva);
  }

  Widget _filaResumenDialogo(String etiqueta, String valor, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(etiqueta,
              style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              valor,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color ?? AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          GradientHeader(
            titulo: 'Confirmar y pagar',
            subtitulo: widget.cancha.nombre,
            mostrarAtras: true,
            paddingInferior: 26,
            contenidoInferior: _resumenReserva(),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('¿Cómo quieres pagar?',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 14),

                  _opcionMetodo(
                    metodo: MetodoPago.tarjeta,
                    titulo: 'Tarjeta de crédito o débito',
                    descripcion:
                        'Serás redirigido a la pasarela segura de Recurrente para completar el pago.',
                    insignia: 'INMEDIATO',
                    colorInsignia: AppColors.primary,
                  ),
                  const SizedBox(height: 10),
                  _opcionMetodo(
                    metodo: MetodoPago.transferencia,
                    titulo: 'Transferencia o depósito',
                    descripcion:
                        'Subes tu comprobante y el administrador confirma el '
                        'depósito.',
                    insignia: 'REQUIERE APROBACIÓN',
                    colorInsignia: AppColors.warning,
                  ),

                  const SizedBox(height: 24),

                  // Formulario de tarjeta reemplazado por un aviso informativo
                  if (_metodo == MetodoPago.tarjeta) 
                    const Aviso(
                      texto: 'Serás redirigido a la pasarela de pago segura de Recurrente (se abrirá en tu navegador). Una vez completado el pago, tu reserva se confirmará automáticamente.',
                      icono: Icons.security_rounded,
                      color: AppColors.primary,
                    ),
                    
                  if (_metodo == MetodoPago.transferencia) _seccionTransferencia(),

                  const SizedBox(height: 22),
                  TextField(
                    controller: _notasCtrl,
                    maxLines: 2,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: 'Notas para el administrador (opcional)',
                      hintText: 'Ej. Llevamos nuestro propio balón',
                      prefixIcon: Icon(Icons.edit_note_rounded),
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Barra inferior fija con el total y el botón de acción.
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 18,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Total',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.inkMuted)),
                      Text(
                        Formato.moneda(widget.montoTotal),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryDark,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _procesando ? null : _confirmar,
                      child: _procesando
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.4, color: Colors.white),
                            )
                          : Text(
                              _metodo == MetodoPago.tarjeta
                                  ? 'IR A PAGAR'
                                  : 'ENVIAR COMPROBANTE',
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resumenReserva() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.sm + 4),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _datoHeader(
              Icons.calendar_today_rounded,
              'Fecha',
              Formato.desdeTexto(widget.fecha, conDia: false),
            ),
          ),
          Container(
            width: 1,
            height: 34,
            color: Colors.white.withValues(alpha: 0.25),
          ),
          Expanded(
            child: _datoHeader(
              Icons.schedule_rounded,
              'Horario',
              '${widget.horaInicio} - ${widget.horaFin}',
            ),
          ),
        ],
      ),
    );
  }

  Widget _datoHeader(IconData icono, String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Icon(icono, size: 18, color: Colors.white.withValues(alpha: 0.9)),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  etiqueta,
                  style: TextStyle(
                      fontSize: 11, color: Colors.white.withValues(alpha: 0.8)),
                ),
                Text(
                  valor,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _opcionMetodo({
    required MetodoPago metodo,
    required String titulo,
    required String descripcion,
    required String insignia,
    required Color colorInsignia,
  }) {
    final seleccionado = _metodo == metodo;

    return Material(
      color: seleccionado ? AppColors.primary.withValues(alpha: 0.05) : Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: _procesando ? null : () => setState(() => _metodo = metodo),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: seleccionado ? AppColors.primary : AppColors.border,
              width: seleccionado ? 1.9 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: seleccionado
                      ? AppColors.primary.withValues(alpha: 0.13)
                      : AppColors.background,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  metodo.icono,
                  size: 21,
                  color: seleccionado ? AppColors.primary : AppColors.inkSoft,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            titulo,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      descripcion,
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.inkSoft, height: 1.35),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colorInsignia.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        insignia,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: colorInsignia,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                seleccionado
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: seleccionado ? AppColors.primary : AppColors.inkMuted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Transferencia
  // ---------------------------------------------------------------------------

  Widget _seccionTransferencia() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Aviso(
          texto: 'Tu reserva quedará PENDIENTE hasta que el administrador '
              'verifique el depósito. Te enviaremos una notificación cuando '
              'la confirme.',
          icono: Icons.hourglass_top_rounded,
          color: AppColors.warning,
        ),
        const SizedBox(height: 18),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.account_balance_rounded,
                      size: 19, color: AppColors.primary),
                  const SizedBox(width: 9),
                  const Text(
                    'Datos para tu depósito',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Copiar número de cuenta',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    onPressed: () {
                      Clipboard.setData(
                          const ClipboardData(text: '000-1234567-8'));
                      mostrarMensaje(context, 'Número de cuenta copiado',
                          esExito: true);
                    },
                  ),
                ],
              ),
              const Divider(height: 20),
              const FilaDato(
                icono: Icons.account_balance_outlined,
                etiqueta: 'Banco',
                valor: ' BI',
              ),
              const FilaDato(
                icono: Icons.numbers_rounded,
                etiqueta: 'Cuenta monetaria',
                valor: '000-1234567-8',
              ),
              const FilaDato(
                icono: Icons.badge_outlined,
                etiqueta: 'A nombre de',
                valor: 'Canchas Ya! S.A.',
              ),
              FilaDato(
                icono: Icons.payments_rounded,
                etiqueta: 'Monto exacto a depositar',
                valor: Formato.moneda(widget.montoTotal),
                colorValor: AppColors.primaryDark,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Foto del comprobante',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        const Text(
          'Asegúrate de que se lean el monto, la fecha y el número de boleta.',
          style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _procesando ? null : _menuComprobante,
          child: _comprobante == null
              ? DottedBox(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.add_a_photo_rounded,
                            color: AppColors.primary, size: 24),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Toca para adjuntar tu comprobante',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Cámara o galería',
                        style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                      ),
                    ],
                  ),
                )
              : Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: Image.file(
                        _comprobante!,
                        height: 220,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _menuComprobante,
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.edit_rounded,
                                color: Colors.white, size: 18),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.check_rounded,
                                color: Colors.white, size: 14),
                            SizedBox(width: 5),
                            Text(
                              'Comprobante listo',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Caja con borde punteado para la zona de "subir comprobante".
class DottedBox extends StatelessWidget {
  final Widget child;
  final double altura;

  const DottedBox({super.key, required this.child, this.altura = 170});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: altura,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.35),
          width: 1.6,
        ),
      ),
      child: child,
    );
  }
}