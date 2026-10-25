import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/login_screen.dart';
import 'screens/seleccion_complejo_screen.dart';
import 'services/api_service.dart';
import 'services/notificacion_service.dart';
import 'theme/app_theme.dart';
import 'widgets/app_widgets.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase (lee android/app/google-services.json).
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase no se pudo inicializar: $e');
  }

  // Recordatorios locales de reservas.
  try {
    await NotificacionService.init();
  } catch (e) {
    debugPrint('Notificaciones no disponibles: $e');
  }

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Reserva Tu Cancha',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const _PuertaDeEntrada(),
    );
  }
}

/// Decide si mostrar el login o entrar directo.
///
/// Si hay sesión guardada, se muestra [SeleccionComplejoScreen], que a su vez
/// SIEMPRE arranca mostrando el selector de complejos.
class _PuertaDeEntrada extends StatefulWidget {
  const _PuertaDeEntrada();

  @override
  State<_PuertaDeEntrada> createState() => _PuertaDeEntradaState();
}

class _PuertaDeEntradaState extends State<_PuertaDeEntrada> {
  late final Future<bool> _sesion;

  @override
  void initState() {
    super.initState();
    _sesion = _verificarSesion();
  }

  Future<bool> _verificarSesion() async {
    final hay = await ApiService.haySesion();
    if (hay) {
      // Pedimos el permiso de notificaciones y reprogramamos los
      // recordatorios de las reservas que siguen vigentes.
      await NotificacionService.pedirPermisos();
      final proximas = await ApiService.getReservasProximas();
      await NotificacionService.sincronizarRecordatorios(proximas);
    }
    return hay;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _sesion,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _PantallaCarga();
        }
        return snapshot.data == true
            ? const SeleccionComplejoScreen()
            : const LoginScreen();
      },
    );
  }
}

class _PantallaCarga extends StatelessWidget {
  const _PantallaCarga();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.heroGradient),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.sports_soccer_rounded, size: 84, color: Colors.white),
              SizedBox(height: 20),
              Text(
                'Reserva Tu Cancha',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: 30),
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cierra la sesión y devuelve al usuario al login.
Future<void> cerrarSesionYSalir(BuildContext context) async {
  await ApiService.cerrarSesion();
  // Olvidamos también el complejo elegido: al volver a entrar, el usuario
  // verá de nuevo la pantalla de selección.
  await ApiService.olvidarComplejo();
  await NotificacionService.cancelarTodo();
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginScreen()),
    (route) => false,
  );
  mostrarMensaje(context, 'Sesión cerrada');
}