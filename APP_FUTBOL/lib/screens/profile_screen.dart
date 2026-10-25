import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../main.dart' show cerrarSesionYSalir;
import '../models/usuario_model.dart';
import '../services/api_service.dart';
import '../services/notificacion_service.dart';
import '../theme/app_theme.dart';
import '../utils/formato.dart';
import '../widgets/app_widgets.dart';
import 'admin_reservas_screen.dart';
import 'editar_perfil_screen.dart';

/// Perfil del usuario: toda su información, sus estadísticas de reservas,
/// los ajustes de recordatorios y el acceso a editar sus datos.
class PerfilScreen extends StatefulWidget {
  /// Opcional: si no se pasa, se usa el correo de la sesión actual.
  final String? userEmail;

  const PerfilScreen({super.key, this.userEmail});

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  Usuario? _usuario;
  bool _cargando = true;
  String? _error;
  int _fotoVersion = 0;

  // Estadísticas
  int _totalReservas = 0;
  int _confirmadas = 0;
  int _pendientes = 0;
  double _totalGastado = 0;

  // Ajustes de notificaciones
  bool _notificacionesActivas = true;
  int _anticipacionHoras = 2;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (mounted) setState(() => _cargando = true);

    final perfil = await ApiService.obtenerPerfil(widget.userEmail);
    final reservas = await ApiService.getTodasMisReservas();
    final activas = await NotificacionService.notificacionesActivas();
    final horas = await NotificacionService.anticipacionHoras();

    if (!mounted) return;
    setState(() {
      _usuario = perfil.datos;
      _error = perfil.exito ? null : perfil.mensaje;
      _totalReservas = reservas.length;
      _confirmadas = reservas
          .where((r) =>
              r.estadoEfectivo.name == 'confirmada' ||
              r.estadoEfectivo.name == 'completada')
          .length;
      _pendientes = reservas.where((r) => r.esperandoAprobacion).length;
      _totalGastado = reservas
          .where((r) => r.estadoEfectivo.name != 'cancelada' &&
              r.estadoEfectivo.name != 'rechazada')
          .fold<double>(0, (suma, r) => suma + r.montoTotal);
      _notificacionesActivas = activas;
      _anticipacionHoras = horas;
      _cargando = false;
    });
  }

Future<void> _editar() async {
  if (_usuario == null) return;

  final actualizado = await Navigator.push<Usuario>(
    context,
    MaterialPageRoute(
      builder: (_) => EditarPerfilScreen(usuario: _usuario!),
    ),
  );

  if (actualizado != null && mounted) {
    setState(() {
      _usuario = actualizado;
      _fotoVersion++;
     });
      }
     }


  Future<void> _cambiarFotoRapido() async {
    if (_usuario == null) return;

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

    setState(() => _cargando = true);
    final resultado = await ApiService.actualizarPerfil(
      email: _usuario!.email,
      fotoFile: File(archivo.path),
    );
    if (!mounted) return;

    if (resultado.exito) {
  if (!mounted) return;

  setState(() {
    if (resultado.datos != null) {
      _usuario = resultado.datos!;
    }

    _fotoVersion++;
    _cargando = false;
  });

  mostrarMensaje(
    context,
    'Foto actualizada',
    esExito: true,
  );

    } else {
      setState(() => _cargando = false);
      mostrarMensaje(context, resultado.mensaje ?? 'No se pudo subir la foto',
          esError: true);
    }
  }

  Future<void> _cambiarPassword() async {
    final actualCtrl = TextEditingController();
    final nuevaCtrl = TextEditingController();
    final repetirCtrl = TextEditingController();
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
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: repetirCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Repite la nueva contraseña',
                      prefixIcon: Icon(Icons.lock_rounded),
                      isDense: true,
                    ),
                    validator: (v) =>
                        v != nuevaCtrl.text ? 'Las contraseñas no coinciden' : null,
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
                        email: _usuario?.email ?? '',
                        oldPassword: actualCtrl.text,
                        newPassword: nuevaCtrl.text,
                      );

                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (!mounted) return;
                      mostrarMensaje(
                        context,
                        resultado.exito
                            ? 'Contraseña actualizada'
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

  Future<void> _probarNotificacion() async {
    await NotificacionService.pedirPermisos();
    await NotificacionService.notificacionDePrueba();
    if (!mounted) return;
    mostrarMensaje(context, 'Notificación enviada', esExito: true);
  }

  Future<void> _confirmarCerrarSesion() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        content: const Text(
            'Tendrás que iniciar sesión de nuevo para ver tus reservas.'),
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
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;
    await cerrarSesionYSalir(context);
  }

  Future<void> _elegirAnticipacion() async {
    final opciones = [1, 2, 3, 6, 12];
    final elegida = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            const Text(
              '¿Cuánto antes quieres el recordatorio?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 30),
              child: Text(
                'Además siempre te avisamos el día anterior.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
              ),
            ),
            const SizedBox(height: 12),
            for (final h in opciones)
              ListTile(
                leading: Icon(
                  h == _anticipacionHoras
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: h == _anticipacionHoras
                      ? AppColors.primary
                      : AppColors.inkMuted,
                ),
                title: Text('$h ${h == 1 ? 'hora' : 'horas'} antes'),
                onTap: () => Navigator.pop(ctx, h),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (elegida == null) return;
    await NotificacionService.setAnticipacionHoras(elegida);
    // Reprogramamos con la nueva anticipación.
    final proximas = await ApiService.getReservasProximas();
    await NotificacionService.sincronizarRecordatorios(proximas);

    if (!mounted) return;
    setState(() => _anticipacionHoras = elegida);
    mostrarMensaje(context, 'Te avisaremos $elegida h antes de cada partido',
        esExito: true);
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_cargando && _usuario == null) {
      return const Scaffold(body: Cargando(texto: 'Cargando tu perfil...'));
    }

    final usuario = _usuario;
    if (usuario == null) {
      return Scaffold(
        body: EstadoVacio(
          icono: Icons.person_off_outlined,
          titulo: 'No pudimos cargar tu perfil',
          mensaje: _error ?? 'Revisa tu conexión e inténtalo de nuevo.',
          accionTexto: 'Reintentar',
          onAccion: _cargar,
        ),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _cargar,
        color: AppColors.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            _encabezado(usuario),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Completitud del perfil
                  if (usuario.completitud < 1) ...[
                    _tarjetaCompletitud(usuario),
                    const SizedBox(height: 20),
                  ],

                  // Estadísticas
                  Text('Resumen', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _tarjetaEstadistica(
                          icono: Icons.event_note_rounded,
                          valor: '$_totalReservas',
                          etiqueta: 'Reservas',
                          color: AppColors.info,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _tarjetaEstadistica(
                          icono: Icons.verified_rounded,
                          valor: '$_confirmadas',
                          etiqueta: 'Confirmadas',
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _tarjetaEstadistica(
                          icono: Icons.hourglass_top_rounded,
                          valor: '$_pendientes',
                          etiqueta: 'Pendientes',
                          color: AppColors.warning,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _tarjetaEstadistica(
                          icono: Icons.payments_rounded,
                          valor: Formato.moneda(_totalGastado),
                          etiqueta: 'Total invertido',
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ],
                  ),

                  // Información personal
                  const SizedBox(height: 24),
                  SeccionTitulo(
                    titulo: 'Mi información',
                    accionTexto: 'Editar',
                    onAccion: _editar,
                  ),
                  const SizedBox(height: 12),
                  AppCard(
                    child: Column(
                      children: [
                        FilaDato(
                          icono: Icons.person_outline_rounded,
                          etiqueta: 'Nombre completo',
                          valor: usuario.nombre,
                        ),
                        FilaDato(
                          icono: Icons.email_outlined,
                          etiqueta: 'Correo electrónico',
                          valor: usuario.email,
                        ),
                        FilaDato(
                          icono: Icons.phone_outlined,
                          etiqueta: 'Teléfono',
                          valor: usuario.telefono ?? 'Sin registrar',
                          colorValor: (usuario.telefono ?? '').isEmpty
                              ? AppColors.inkMuted
                              : null,
                        ),
                        FilaDato(
                          icono: Icons.home_outlined,
                          etiqueta: 'Dirección',
                          valor: usuario.direccion ?? 'Sin registrar',
                          colorValor: (usuario.direccion ?? '').isEmpty
                              ? AppColors.inkMuted
                              : null,
                        ),
                        FilaDato(
                          icono: Icons.cake_outlined,
                          etiqueta: 'Fecha de nacimiento',
                          valor: usuario.fechaNacimiento != null
                              ? Formato.fechaLarga(usuario.fechaNacimiento)
                              : 'Sin registrar',
                          colorValor: usuario.fechaNacimiento == null
                              ? AppColors.inkMuted
                              : null,
                        ),
                        FilaDato(
                          icono: Icons.badge_outlined,
                          etiqueta: 'Tipo de cuenta',
                          valor: usuario.esAdmin ? 'Administrador' : 'Cliente',
                        ),
                        if (usuario.fechaRegistro != null)
                          FilaDato(
                            icono: Icons.calendar_month_outlined,
                            etiqueta: 'Miembro desde',
                            valor: Formato.fechaLarga(usuario.fechaRegistro),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _editar,
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      label: const Text('EDITAR MIS DATOS'),
                    ),
                  ),

                  // Recordatorios
                  const SizedBox(height: 24),
                  Text('Recordatorios',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  AppCard(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 4),
                    child: Column(
                      children: [
                        SwitchListTile(
                          value: _notificacionesActivas,
                          activeThumbColor: AppColors.primary,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 10),
                          title: const Text('Avisos de mis reservas'),
                          subtitle: const Text(
                            'Recordatorios antes del partido y avisos cuando '
                            'se confirma tu pago',
                            style: TextStyle(fontSize: 12.5),
                          ),
                          onChanged: (valor) async {
                            await NotificacionService.setNotificacionesActivas(
                                valor);
                            if (valor) {
                              await NotificacionService.pedirPermisos();
                              final proximas =
                                  await ApiService.getReservasProximas();
                              await NotificacionService
                                  .sincronizarRecordatorios(proximas);
                            }
                            if (!mounted) return;
                            setState(() => _notificacionesActivas = valor);
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          enabled: _notificacionesActivas,
                          leading: const Icon(Icons.timer_outlined),
                          title: const Text('Anticipación del aviso'),
                          subtitle: Text(
                            '$_anticipacionHoras '
                            '${_anticipacionHoras == 1 ? 'hora' : 'horas'} '
                            'antes del partido',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: _notificacionesActivas
                              ? _elegirAnticipacion
                              : null,
                        ),
                        const Divider(height: 1),
                        ListTile(
                          enabled: _notificacionesActivas,
                          leading: const Icon(Icons.notifications_active_outlined),
                          title: const Text('Probar una notificación'),
                          subtitle: const Text(
                            'Comprueba que los avisos llegan a tu teléfono',
                            style: TextStyle(fontSize: 12.5),
                          ),
                          trailing: const Icon(Icons.play_arrow_rounded),
                          onTap: _notificacionesActivas
                              ? _probarNotificacion
                              : null,
                        ),
                      ],
                    ),
                  ),

                  // Cuenta
                  const SizedBox(height: 24),
                  Text('Cuenta', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  AppCard(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 4),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.lock_reset_rounded),
                          title: const Text('Cambiar contraseña'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: _cambiarPassword,
                        ),
                        if (usuario.esAdmin) ...[
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(
                                Icons.admin_panel_settings_rounded,
                                color: AppColors.info),
                            title: const Text('Aprobar reservas'),
                            subtitle: Text(
                              _pendientes > 0
                                  ? 'Hay depósitos por validar'
                                  : 'Validar depósitos por transferencia',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const AdminReservasScreen()),
                              );
                              if (mounted) _cargar();
                            },
                          ),
                        ],
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.logout_rounded,
                              color: AppColors.danger),
                          title: const Text('Cerrar sesión',
                              style: TextStyle(color: AppColors.danger)),
                          onTap: _confirmarCerrarSesion,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),
                  Center(
                    child: Text(
                      'Canchas Ya! · versión 1.0.0',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.inkMuted.withValues(alpha: 0.9)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _encabezado(Usuario usuario) {
    final fotoBase = ApiService.urlAbsoluta(usuario.fotoUrl);

      final fotoUrl = fotoBase == null
     ? null
     : '$fotoBase?v=$_fotoVersion';

     return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(AppRadius.lg + 6),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 26),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Mi perfil',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  HeaderIconButton(
                    icono: Icons.edit_rounded,
                    tooltip: 'Editar perfil',
                    onTap: _editar,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.6), width: 3),
                    ),
                    child: CircleAvatar(
                      radius: 48,
                      backgroundColor: Colors.white.withValues(alpha: 0.22),
                      backgroundImage:
                          fotoUrl != null ? NetworkImage(fotoUrl) : null,
                      child: fotoUrl == null
                          ? Text(
                              usuario.iniciales,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                              ),
                            )
                          : null,
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Material(
                      color: Colors.white,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _cambiarFotoRapido,
                        child: const Padding(
                          padding: EdgeInsets.all(7),
                          child: Icon(Icons.camera_alt_rounded,
                              size: 17, color: AppColors.primaryDark),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                usuario.nombre.isEmpty ? 'Sin nombre' : usuario.nombre,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                usuario.email,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85), fontSize: 13.5),
              ),
              if (usuario.esAdmin) ...[
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shield_rounded, size: 14, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        'ADMINISTRADOR',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaCompletitud(Usuario usuario) {
    final porcentaje = (usuario.completitud * 100).round();
    return AppCard(
      onTap: _editar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pie_chart_outline_rounded,
                  size: 19, color: AppColors.warning),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Completa tu perfil',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '$porcentaje%',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: usuario.completitud,
              minHeight: 7,
              backgroundColor: AppColors.background,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.warning),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Agrega tu teléfono y dirección para que podamos contactarte '
            'si hay algún cambio en tu reserva.',
            style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaEstadistica({
    required IconData icono,
    required String valor,
    required String etiqueta,
    required Color color,
  }) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icono, size: 18, color: color),
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valor,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            etiqueta,
            style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }
}
