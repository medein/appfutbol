import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/usuario_model.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/formato.dart';
import '../widgets/app_widgets.dart';

/// Formulario para actualizar los datos del usuario.
/// Devuelve el `Usuario` actualizado al guardar.
class EditarPerfilScreen extends StatefulWidget {
  final Usuario usuario;

  const EditarPerfilScreen({super.key, required this.usuario});

  @override
  State<EditarPerfilScreen> createState() => _EditarPerfilScreenState();
}

class _EditarPerfilScreenState extends State<EditarPerfilScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _telefonoCtrl;
  late final TextEditingController _direccionCtrl;

  DateTime? _fechaNacimiento;
  File? _fotoNueva;
  bool _guardando = false;
  String? _cacheFoto;

  @override
  void initState() {
    super.initState();
    _nombreCtrl = TextEditingController(text: widget.usuario.nombre);
    _telefonoCtrl = TextEditingController(text: widget.usuario.telefono ?? '');
    _direccionCtrl = TextEditingController(text: widget.usuario.direccion ?? '');
    _fechaNacimiento = widget.usuario.fechaNacimiento;

    // Al escribir se reevalúa si hay cambios, para habilitar el botón Guardar.
    for (final ctrl in [_nombreCtrl, _telefonoCtrl, _direccionCtrl]) {
      ctrl.addListener(_alEscribir);
    }
  }

  void _alEscribir() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final ctrl in [_nombreCtrl, _telefonoCtrl, _direccionCtrl]) {
      ctrl.removeListener(_alEscribir);
      ctrl.dispose();
    }
    super.dispose();
  }

  bool get _hayCambios {
    return _nombreCtrl.text.trim() != widget.usuario.nombre ||
        _telefonoCtrl.text.trim() != (widget.usuario.telefono ?? '') ||
        _direccionCtrl.text.trim() != (widget.usuario.direccion ?? '') ||
        _fechaNacimiento != widget.usuario.fechaNacimiento ||
        _fotoNueva != null;
  }

  Future<void> _elegirFoto() async {
    final origen = await showModalBottomSheet<ImageSource>(
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

    try {
      final archivo =
          await ImagePicker().pickImage(source: origen, imageQuality: 80);
      if (archivo != null && mounted) {
        setState(() => _fotoNueva = File(archivo.path));
      }
    } catch (e) {
      if (mounted) {
        mostrarMensaje(context, 'No pudimos abrir la cámara o la galería',
            esError: true);
      }
    }
  }

  Future<void> _elegirFechaNacimiento() async {
    final ahora = DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fechaNacimiento ?? DateTime(ahora.year - 25),
      firstDate: DateTime(1930),
      lastDate: ahora,
      helpText: 'Tu fecha de nacimiento',
      cancelText: 'Cancelar',
      confirmText: 'Listo',
    );
    if (elegida != null) setState(() => _fechaNacimiento = elegida);
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _guardando = true);

    final resultado = await ApiService.actualizarPerfil(
      email: widget.usuario.email,
      nombre: _nombreCtrl.text.trim(),
      telefono: _telefonoCtrl.text.trim(),
      direccion: _direccionCtrl.text.trim(),
      fechaNacimiento: _fechaNacimiento,
      fotoFile: _fotoNueva,
    );

    if (!mounted) return;
    setState(() => _guardando = false);

    if (!resultado.exito) {
      mostrarMensaje(context, resultado.mensaje ?? 'No se pudo guardar',
          esError: true);
      return;
    }

    mostrarMensaje(context, 'Tus datos se actualizaron', esExito: true);

    // Devolvemos el usuario con lo que escribió el usuario, por si el backend
    // no repite todos los campos en su respuesta.
    final usuarioServidor = resultado.datos ?? widget.usuario;

String? nuevaFotoUrl = usuarioServidor.fotoUrl;

if (nuevaFotoUrl != null && nuevaFotoUrl.isNotEmpty) {
  nuevaFotoUrl =
      '$nuevaFotoUrl?v=${DateTime.now().millisecondsSinceEpoch}';
}

  final actualizado = usuarioServidor.copyWith(
  nombre: _nombreCtrl.text.trim(),
  telefono: _telefonoCtrl.text.trim(),
  direccion: _direccionCtrl.text.trim(),
  fechaNacimiento: _fechaNacimiento,
  fotoUrl: nuevaFotoUrl,
  );

Navigator.pop(context, actualizado);
  }

  Future<bool> _confirmarSalida() async {
    if (!_hayCambios) return true;

    final salir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Descartar los cambios?'),
        content: const Text('Los datos que escribiste no se guardarán.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: AppColors.inkSoft),
            child: const Text('Seguir editando'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              minimumSize: const Size(0, 44),
            ),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    return salir == true;
  }

  // ---------------------------------------------------------------------------

  @override
Widget build(BuildContext context) {
  final fotoBase = ApiService.urlAbsoluta(widget.usuario.fotoUrl);

  // Evita que Flutter muestre la foto anterior desde caché.
  final fotoServidor = fotoBase != null
      ? '$fotoBase?v=${DateTime.now().millisecondsSinceEpoch}'
      : null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmarSalida() && mounted) {
          if (!context.mounted) return;
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        body: Column(
          children: [
            GradientHeader(
              titulo: 'Editar mis datos',
              subtitulo: widget.usuario.email,
              mostrarAtras: true,
              onAtras: () async {
                if (await _confirmarSalida() && mounted) {
                  if (!context.mounted) return;
                  Navigator.pop(context);
                }
              },
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Foto
                      Center(
                        child: Column(
                          children: [
                            Stack(
                              children: [
                                CircleAvatar(
                                  radius: 52,
                                  backgroundColor: AppColors.background,
                                  backgroundImage: _fotoNueva != null
                                      ? FileImage(_fotoNueva!)
                                      : (fotoServidor != null
                                          ? NetworkImage(fotoServidor)
                                              as ImageProvider
                                          : null),
                                  child: (_fotoNueva == null &&
                                          fotoServidor == null)
                                      ? Text(
                                          widget.usuario.iniciales,
                                          style: const TextStyle(
                                            fontSize: 32,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.inkMuted,
                                          ),
                                        )
                                      : null,
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Material(
                                    color: AppColors.primary,
                                    shape: const CircleBorder(),
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: _guardando ? null : _elegirFoto,
                                      child: const Padding(
                                        padding: EdgeInsets.all(8),
                                        child: Icon(Icons.camera_alt_rounded,
                                            size: 17, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: _guardando ? null : _elegirFoto,
                              child: Text(_fotoNueva == null
                                  ? 'Cambiar foto de perfil'
                                  : 'Elegir otra foto'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      const Text(
                        'Datos personales',
                        style:
                            TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 14),

                      TextFormField(
                        controller: _nombreCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Nombre completo',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                        validator: (v) {
                          final texto = (v ?? '').trim();
                          if (texto.isEmpty) return 'Ingresa tu nombre';
                          if (texto.length < 3) return 'El nombre es muy corto';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // El correo no se edita: es la llave de la cuenta.
                      TextFormField(
                        initialValue: widget.usuario.email,
                        enabled: false,
                        decoration: const InputDecoration(
                          labelText: 'Correo electrónico',
                          prefixIcon: Icon(Icons.email_outlined),
                          helperText: 'El correo de tu cuenta no se puede cambiar',
                          fillColor: AppColors.background,
                        ),
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _telefonoCtrl,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9+\-() ]')),
                          LengthLimitingTextInputFormatter(20),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Teléfono',
                          hintText: '5555-5555',
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                        validator: (v) {
                          final digitos = (v ?? '').replaceAll(RegExp(r'\D'), '');
                          if (digitos.isEmpty) return null; // es opcional
                          if (digitos.length < 8) {
                            return 'Ingresa un teléfono válido (8 dígitos)';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _direccionCtrl,
                        textCapitalization: TextCapitalization.sentences,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Dirección',
                          hintText: 'Zona, colonia, referencias...',
                          prefixIcon: Icon(Icons.home_outlined),
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Fecha de nacimiento
                      InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                        onTap: _guardando ? null : _elegirFechaNacimiento,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 17),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius:
                                BorderRadius.circular(AppRadius.sm + 2),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.cake_outlined,
                                  size: 21, color: AppColors.inkSoft),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Fecha de nacimiento',
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          color: AppColors.inkMuted),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _fechaNacimiento == null
                                          ? 'Sin registrar'
                                          : Formato.fechaLarga(_fechaNacimiento),
                                      style: TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w600,
                                        color: _fechaNacimiento == null
                                            ? AppColors.inkMuted
                                            : AppColors.ink,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_fechaNacimiento != null)
                                IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 18),
                                  onPressed: () =>
                                      setState(() => _fechaNacimiento = null),
                                )
                              else
                                const Icon(Icons.chevron_right_rounded,
                                    color: AppColors.inkMuted),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 26),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: (_guardando || !_hayCambios) ? null : _guardar,
                          child: _guardando
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.4, color: Colors.white),
                                )
                              : Text(_hayCambios
                                  ? 'GUARDAR CAMBIOS'
                                  : 'SIN CAMBIOS POR GUARDAR'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _guardando
                              ? null
                              : () async {
                                  if (await _confirmarSalida() && mounted) {
                                    if (!context.mounted) return;
                                    Navigator.pop(context);
                                  }
                                },
                          child: const Text('Cancelar'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
