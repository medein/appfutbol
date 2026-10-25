import 'package:flutter/material.dart';

import '../models/mensaje_chat.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/formato.dart';
import '../widgets/app_widgets.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<MensajeChat> _mensajes = [];

  bool _enviando = false;
  bool _cargandoHistorial = true;

  /// Sugerencias rápidas para que el usuario no empiece desde cero.
  static const List<String> _sugerencias = [
    'Quiero reservar una cancha',
    '¿Qué canchas están libres hoy?',
    '¿Cuánto cuesta una hora?',
    'Ver mis reservas',
  ];

  @override
  void initState() {
    super.initState();
    _cargarHistorial();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _bajarAlFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0, // con reverse: true, 0 es el final de la conversación
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _cargarHistorial() async {
    setState(() => _cargandoHistorial = true);
    final historial = await ApiService.getHistorialChat();
    if (!mounted) return;
    setState(() {
      _mensajes
        ..clear()
        ..addAll(historial);
      _cargandoHistorial = false;
    });
  }

  Future<void> _enviar([String? texto]) async {
    final mensaje = (texto ?? _controller.text).trim();
    if (mensaje.isEmpty || _enviando) return;

    setState(() {
      _mensajes.add(MensajeChat(
        mensajeUsuario: mensaje,
        esUsuario: true,
        fecha: DateTime.now(),
      ));
      _controller.clear();
      _enviando = true;
    });
    _bajarAlFinal();

    try {
      final resultado = await ApiService.enviarMensaje(mensaje);
      if (!mounted) return;
      setState(() {
        _mensajes.add(MensajeChat(
          mensajeUsuario: resultado['respuesta'] ?? 'Sin respuesta',
          esUsuario: false,
          fecha: DateTime.now(),
          intencion: resultado['intencion'],
          opciones: List<String>.from(resultado['opciones'] ?? const []),
        ));
      });

      final accion = resultado['accion_resultado'];
      if (accion != null && mounted) {
        final textoAccion = accion is Map
            ? (accion['mensaje'] ?? accion.toString())
            : accion.toString();
        mostrarMensaje(context, textoAccion.toString());
      }
    } catch (e) {
      if (!mounted) return;
      final detalle = e.toString().replaceAll('Exception: ', '');
      setState(() {
        _mensajes.add(MensajeChat(
          mensajeUsuario:
              'No pude responder ahora mismo. $detalle\n\nIntenta de nuevo '
              'en un momento.',
          esUsuario: false,
          fecha: DateTime.now(),
        ));
      });
    } finally {
      if (mounted) {
        setState(() => _enviando = false);
        _bajarAlFinal();
      }
    }
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Si la última respuesta del asistente trae botones (ej. Confirmar),
    // se muestran en lugar de las sugerencias generales.
    final opcionesActuales = (_mensajes.isNotEmpty &&
            !_mensajes.last.esUsuario &&
            !_enviando)
        ? _mensajes.last.opciones
        : const <String>[];

    return Scaffold(
      body: Column(
        children: [
          GradientHeader(
            titulo: 'Asistente',
            subtitulo:
                _enviando ? 'Escribiendo...' : 'Pregúntame lo que necesites',
            acciones: [
              HeaderIconButton(
                icono: Icons.refresh_rounded,
                tooltip: 'Recargar la conversación',
                onTap: _cargarHistorial,
              ),
            ],
            paddingInferior: 18,
          ),
          Expanded(
            child: _cargandoHistorial
                ? const Cargando(texto: 'Cargando tu conversación...')
                : _mensajes.isEmpty
                    ? _bienvenida()
                    : ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                        itemCount: _mensajes.length + (_enviando ? 1 : 0),
                        itemBuilder: (context, index) {
                          // El indicador "escribiendo" va al final visual.
                          if (_enviando && index == 0) {
                            return _burbujaEscribiendo();
                          }
                          final i = _enviando ? index - 1 : index;
                          final msg = _mensajes[_mensajes.length - 1 - i];
                          return _burbuja(msg);
                        },
                      ),
          ),
          if (_mensajes.isNotEmpty)
            opcionesActuales.isNotEmpty
                ? _filaOpciones(opcionesActuales)
                : _filaSugerencias(),
          _campoEntrada(),
        ],
      ),
    );
  }

  Widget _bienvenida() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 34, 28, 20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.09),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.smart_toy_rounded,
                size: 42, color: AppColors.primary),
          ),
          const SizedBox(height: 20),
          const Text(
            '¿En qué te ayudo?',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Puedo consultar canchas, hacer tu reserva, revisar tus reservas '
            'y explicarte cómo funcionan los pagos.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14, color: AppColors.inkSoft, height: 1.45),
          ),
          const SizedBox(height: 28),
          for (final sugerencia in _sugerencias) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _enviando ? null : () => _enviar(sugerencia),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  backgroundColor: const Color.fromARGB(255, 54, 244, 114),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline_rounded,
                        size: 16, color: AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        sugerencia,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _filaSugerencias() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final s in _sugerencias)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                label: Text(s, style: const TextStyle(fontSize: 12)),
                backgroundColor: const Color.fromARGB(255, 14, 159, 10),
                onPressed: _enviando ? null : () => _enviar(s),
              ),
            ),
        ],
      ),
    );
  }

  /// Botones que propone el asistente para responder con un toque
  /// (por ejemplo "Sí, confirmar" / "No, cambiar").
  Widget _filaOpciones(List<String> opciones) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          for (final o in opciones)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                label: Text(
                  o,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
                onPressed: _enviando ? null : () => _enviar(o),
              ),
            ),
        ],
      ),
    );
  }

  Widget _campoEntrada() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 4,
                minLines: 1,
                enabled: !_enviando,
                decoration: InputDecoration(
                  hintText: 'Escribe tu mensaje...',
                  filled: true,
                  fillColor: AppColors.background,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 13),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    borderSide:
                        const BorderSide(color: AppColors.primary, width: 1.6),
                  ),
                ),
                onSubmitted: (_) => _enviar(),
              ),
            ),
            const SizedBox(width: 10),
            Material(
              color: _enviando ? AppColors.border : AppColors.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _enviando ? null : () => _enviar(),
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: Icon(
                    Icons.send_rounded,
                    color: _enviando ? AppColors.inkMuted : Colors.white,
                    size: 21,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _burbuja(MensajeChat msg) {
    final esUsuario = msg.esUsuario;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment:
            esUsuario ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!esUsuario) ...[
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.smart_toy_rounded,
                  size: 15, color: AppColors.primary),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: esUsuario ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(AppRadius.md),
                  topRight: const Radius.circular(AppRadius.md),
                  bottomLeft: Radius.circular(esUsuario ? AppRadius.md : 4),
                  bottomRight: Radius.circular(esUsuario ? 4 : AppRadius.md),
                ),
                border: esUsuario
                    ? null
                    : Border.all(color: AppColors.border),
                boxShadow: AppShadows.soft,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    msg.mensajeUsuario,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.45,
                      color: esUsuario ? Colors.white : AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    Formato.hora(msg.fecha),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: esUsuario
                          ? Colors.white.withValues(alpha: 0.75)
                          : AppColors.inkMuted,
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

  Widget _burbujaEscribiendo() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.smart_toy_rounded,
                size: 15, color: AppColors.primary),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppRadius.md),
                topRight: Radius.circular(AppRadius.md),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(AppRadius.md),
              ),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text(
                  'Escribiendo...',
                  style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}