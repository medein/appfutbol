import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../services/notificacion_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import 'main_shell.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _repetirCtrl = TextEditingController();

  bool _cargando = false;
  bool _verPassword = false;
  bool _aceptaTerminos = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _emailCtrl.dispose();
    _telefonoCtrl.dispose();
    _passwordCtrl.dispose();
    _repetirCtrl.dispose();
    super.dispose();
  }

  Future<void> _registrar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (!_aceptaTerminos) {
      mostrarMensaje(
        context,
        'Debes aceptar los términos para crear tu cuenta',
        esError: true,
      );
      return;
    }

    setState(() => _cargando = true);
    final resultado = await ApiService.register(
      nombre: _nombreCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
      telefono: _telefonoCtrl.text.trim(),
    );
    if (!mounted) return;

    if (!resultado.exito) {
      setState(() => _cargando = false);
      mostrarMensaje(context, resultado.mensaje ?? 'No se pudo crear la cuenta',
          esError: true);
      return;
    }

    // Si el backend devolvió el token, entramos directo. Si no, volvemos
    // al login para que inicie sesión.
    if (await ApiService.haySesion()) {
      await NotificacionService.pedirPermisos();
      if (!mounted) return;
      setState(() => _cargando = false);
      mostrarMensaje(context, '¡Bienvenido! Tu cuenta está lista', esExito: true);
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MainShell()),
        (route) => false,
      );
    } else {
      if (!mounted) return;
      setState(() => _cargando = false);
      mostrarMensaje(context, '¡Cuenta creada! Ahora inicia sesión',
          esExito: true);
      Navigator.pop(context);
    }
  }

  /// Fuerza de la contraseña: 0 a 1.
  double get _fuerzaPassword {
    final p = _passwordCtrl.text;
    if (p.isEmpty) return 0;
    int puntos = 0;
    if (p.length >= 6) puntos++;
    if (p.length >= 10) puntos++;
    if (RegExp(r'[A-Z]').hasMatch(p)) puntos++;
    if (RegExp(r'[0-9]').hasMatch(p)) puntos++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) puntos++;
    return puntos / 5;
  }

  String get _textoFuerza {
    final f = _fuerzaPassword;
    if (f == 0) return '';
    if (f <= 0.4) return 'Débil';
    if (f <= 0.7) return 'Aceptable';
    return 'Segura';
  }

  Color get _colorFuerza {
    final f = _fuerzaPassword;
    if (f <= 0.4) return AppColors.danger;
    if (f <= 0.7) return AppColors.warning;
    return AppColors.primary;
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const GradientHeader(
            titulo: 'Crear cuenta',
            subtitulo: 'Regístrate para empezar a reservar',
            mostrarAtras: true,
            paddingInferior: 26,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _nombreCtrl,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      enabled: !_cargando,
                      decoration: const InputDecoration(
                        labelText: 'Nombre completo',
                        hintText: 'Juan Pérez',
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

                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      enabled: !_cargando,
                      decoration: const InputDecoration(
                        labelText: 'Correo electrónico',
                        hintText: 'tucorreo@ejemplo.com',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (v) {
                        final texto = (v ?? '').trim();
                        if (texto.isEmpty) return 'Ingresa tu correo';
                        if (!RegExp(r'^[\w.\-+]+@[\w\-]+\.[\w.\-]+$')
                            .hasMatch(texto)) {
                          return 'Ese correo no parece válido';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _telefonoCtrl,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      enabled: !_cargando,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-() ]')),
                        LengthLimitingTextInputFormatter(20),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Teléfono (opcional)',
                        hintText: '5555-5555',
                        prefixIcon: Icon(Icons.phone_outlined),
                        helperText: 'Nos sirve para avisarte de cambios en tu reserva',
                      ),
                      validator: (v) {
                        final digitos = (v ?? '').replaceAll(RegExp(r'\D'), '');
                        if (digitos.isEmpty) return null;
                        if (digitos.length < 8) return 'Teléfono incompleto';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: !_verPassword,
                      textInputAction: TextInputAction.next,
                      enabled: !_cargando,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _verPassword
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            size: 20,
                          ),
                          onPressed: () =>
                              setState(() => _verPassword = !_verPassword),
                        ),
                      ),
                      validator: (v) {
                        if ((v ?? '').isEmpty) return 'Crea una contraseña';
                        if ((v ?? '').length < 6) {
                          return 'Debe tener al menos 6 caracteres';
                        }
                        return null;
                      },
                    ),

                    // Indicador de fuerza
                    if (_passwordCtrl.text.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.pill),
                              child: LinearProgressIndicator(
                                value: _fuerzaPassword,
                                minHeight: 5,
                                backgroundColor: AppColors.border,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(_colorFuerza),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _textoFuerza,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _colorFuerza,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _repetirCtrl,
                      obscureText: !_verPassword,
                      textInputAction: TextInputAction.done,
                      enabled: !_cargando,
                      onFieldSubmitted: (_) => _registrar(),
                      decoration: const InputDecoration(
                        labelText: 'Repite la contraseña',
                        prefixIcon: Icon(Icons.lock_rounded),
                      ),
                      validator: (v) => v != _passwordCtrl.text
                          ? 'Las contraseñas no coinciden'
                          : null,
                    ),
                    const SizedBox(height: 18),

                    // Términos
                    InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      onTap: _cargando
                          ? null
                          : () => setState(
                              () => _aceptaTerminos = !_aceptaTerminos),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Checkbox(
                              value: _aceptaTerminos,
                              activeColor: AppColors.primary,
                              onChanged: _cargando
                                  ? null
                                  : (v) => setState(
                                      () => _aceptaTerminos = v ?? false),
                            ),
                            const Expanded(
                              child: Text(
                                'Acepto los términos de uso y la política de '
                                'privacidad de Canchas Ya!',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.inkSoft,
                                    height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    ElevatedButton(
                      onPressed: _cargando ? null : _registrar,
                      child: _cargando
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.4, color: Colors.white),
                            )
                          : const Text('CREAR MI CUENTA'),
                    ),
                    const SizedBox(height: 14),

                    Center(
                      child: TextButton(
                        onPressed:
                            _cargando ? null : () => Navigator.pop(context),
                        child: const Text('Ya tengo cuenta, iniciar sesión'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
