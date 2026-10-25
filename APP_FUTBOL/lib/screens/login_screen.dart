import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/notificacion_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import 'main_shell.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _cargando = false;
  bool _verPassword = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _cargando = true);
    final resultado = await ApiService.login(
      _emailCtrl.text.trim(),
      _passwordCtrl.text,
    );
    if (!mounted) return;
    setState(() => _cargando = false);

    if (resultado.exito) {
      await _despuesDeEntrar();
    } else {
      mostrarMensaje(context, resultado.mensaje ?? 'Credenciales incorrectas',
          esError: true);
    }
  }

  Future<void> _entrarConGoogle() async {
    setState(() => _cargando = true);
    final resultado = await ApiService.loginConGoogle();
    if (!mounted) return;
    setState(() => _cargando = false);

    if (resultado.exito) {
      await _despuesDeEntrar();
    } else {
      mostrarMensaje(context, resultado.mensaje ?? 'No se pudo entrar con Google',
          esError: true);
    }
  }

  /// Tras entrar, pedimos el permiso de notificaciones y reprogramamos los
  /// recordatorios de las reservas que ya tenía el usuario.
  Future<void> _despuesDeEntrar() async {
    await NotificacionService.pedirPermisos();
    final proximas = await ApiService.getReservasProximas();
    await NotificacionService.sincronizarRecordatorios(proximas);

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const MainShell()),
      (route) => false,
    );
  }

  Future<void> _recuperarPassword() async {
    final emailCtrl = TextEditingController(text: _emailCtrl.text.trim());
    final actualCtrl = TextEditingController();
    final nuevaCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool procesando = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Cambiar contraseña'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Ingresa tu correo y tu contraseña actual para definir '
                    'una nueva.',
                    style: TextStyle(fontSize: 13.5, color: AppColors.inkSoft),
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Correo electrónico',
                      prefixIcon: Icon(Icons.email_outlined),
                      isDense: true,
                    ),
                    validator: _validarEmail,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: actualCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Contraseña actual',
                      prefixIcon: Icon(Icons.lock_outline_rounded),
                      isDense: true,
                    ),
                    validator: (v) =>
                        (v ?? '').isEmpty ? 'Ingresa tu contraseña actual' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: nuevaCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Nueva contraseña',
                      prefixIcon: Icon(Icons.lock_reset_rounded),
                      isDense: true,
                    ),
                    validator: (v) => (v ?? '').length < 6
                        ? 'Debe tener al menos 6 caracteres'
                        : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: procesando ? null : () => Navigator.pop(ctx),
              style: TextButton.styleFrom(foregroundColor: AppColors.inkSoft),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: procesando
                  ? null
                  : () async {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      setDialog(() => procesando = true);

                      final resultado = await ApiService.cambiarPassword(
                        email: emailCtrl.text.trim(),
                        oldPassword: actualCtrl.text,
                        newPassword: nuevaCtrl.text,
                      );

                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (!mounted) return;
                      mostrarMensaje(
                        context,
                        resultado.exito
                            ? '¡Contraseña cambiada con éxito!'
                            : resultado.mensaje ?? 'No se pudo cambiar',
                        esExito: resultado.exito,
                        esError: !resultado.exito,
                      );
                    },
              child: procesando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Colors.white),
                    )
                  : const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  static String? _validarEmail(String? valor) {
    final texto = (valor ?? '').trim();
    if (texto.isEmpty) return 'Ingresa tu correo';
    if (!RegExp(r'^[\w.\-+]+@[\w\-]+\.[\w.\-]+$').hasMatch(texto)) {
      return 'Ese correo no parece válido';
    }
    return null;
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final alto = MediaQuery.of(context).size.height;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.heroGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                  // Logo y bienvenida sobre el degradado
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 42, 28, 34),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                                width: 2),
                          ),
                          child: const Icon(Icons.sports_soccer_rounded,
                              size: 46, color: Colors.white),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Reserva Tu Cancha',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 27,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Aparta tu cancha, paga y juega',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontSize: 14.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Tarjeta clara con el formulario
                  Container(
                      width: double.infinity,
                      constraints: BoxConstraints(minHeight: alto * 0.60),
                      decoration: const BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(AppRadius.lg + 8),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Iniciar sesión',
                                style: TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.ink,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Entra con tu cuenta para ver tus reservas',
                                style: TextStyle(
                                    fontSize: 13.5, color: AppColors.inkSoft),
                              ),
                              const SizedBox(height: 24),

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
                                validator: _validarEmail,
                              ),
                              const SizedBox(height: 16),

                              TextFormField(
                                controller: _passwordCtrl,
                                obscureText: !_verPassword,
                                textInputAction: TextInputAction.done,
                                enabled: !_cargando,
                                onFieldSubmitted: (_) => _entrar(),
                                decoration: InputDecoration(
                                  labelText: 'Contraseña',
                                  prefixIcon:
                                      const Icon(Icons.lock_outline_rounded),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _verPassword
                                          ? Icons.visibility_off_rounded
                                          : Icons.visibility_rounded,
                                      size: 20,
                                    ),
                                    onPressed: () => setState(
                                        () => _verPassword = !_verPassword),
                                  ),
                                ),
                                validator: (v) => (v ?? '').isEmpty
                                    ? 'Ingresa tu contraseña'
                                    : null,
                              ),

                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed:
                                      _cargando ? null : _recuperarPassword,
                                  child: const Text('¿Cambiar contraseña?'),
                                ),
                              ),
                              const SizedBox(height: 6),

                              ElevatedButton(
                                onPressed: _cargando ? null : _entrar,
                                child: _cargando
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2.4,
                                            color: Colors.white),
                                      )
                                    : const Text('INGRESAR'),
                              ),
                              const SizedBox(height: 20),

                              Row(
                                children: [
                                  const Expanded(child: Divider()),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14),
                                    child: Text(
                                      'o continúa con',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: AppColors.inkMuted
                                            .withValues(alpha: 0.95),
                                      ),
                                    ),
                                  ),
                                  const Expanded(child: Divider()),
                                ],
                              ),
                              const SizedBox(height: 20),

                              OutlinedButton.icon(
                                onPressed: _cargando ? null : _entrarConGoogle,
                                icon: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: const Text(
                                    'G',
                                    style: TextStyle(
                                      color: Color(0xFF4285F4),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                label: const Text('Google'),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 24),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    '¿No tienes cuenta?',
                                    style: TextStyle(
                                        fontSize: 13.5,
                                        color: AppColors.inkSoft),
                                  ),
                                  TextButton(
                                    onPressed: _cargando
                                        ? null
                                        : () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    const RegisterScreen(),
                                              ),
                                            ),
                                    child: const Text('Regístrate aquí'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ),
                ],
              ),
            ),
          ),
        ),
    );
  }
}
