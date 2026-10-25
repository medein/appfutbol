import 'package:flutter/material.dart';

import '../models/cancha_model.dart';
import '../models/complejo_model.dart';
import '../models/reserva_model.dart';
import '../services/api_service.dart';
import '../services/notificacion_service.dart';
import '../theme/app_theme.dart';
import '../utils/formato.dart';
import '../widgets/app_widgets.dart';
import 'admin_reservas_screen.dart';
import 'detalle_reserva_screen.dart';
import 'main_shell.dart';
import 'pantalla_pago_screen.dart';

class HomeScreen extends StatefulWidget {
  /// Complejo elegido por el usuario. Si es null, mostramos los chips de
  /// selección para que pueda filtrar entre todos los complejos.
  final Complejo? complejo;

  const HomeScreen({super.key, this.complejo});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Cancha> _canchas = [];
  List<Reserva> _proximas = [];
  List<Complejo> _complejos = [];
  bool _cargando = true;
  bool _esAdmin = false;
  String _busqueda = '';
  String _nombreUsuario = '';
  int? _complejoSeleccionadoId;

  @override
  void initState() {
    super.initState();
    // Si el MainShell nos pasa un complejo, ese es el seleccionado.
    _complejoSeleccionadoId = widget.complejo?.id;
    _cargarTodo();
  }

  // ---------------------------------------------------------------------------
  // Carga de datos
  // ---------------------------------------------------------------------------

  Future<void> _cargarTodo() async {
    setState(() => _cargando = true);

    final canchas = await ApiService.getCanchas();
    final resultadoComplejos = await ApiService.getComplejos();
    final complejos = resultadoComplejos.datos ?? <Complejo>[];

    final proximas = await ApiService.getReservasProximas();
    final admin = await ApiService.esAdmin();
    final perfil = await ApiService.obtenerPerfil();

    await NotificacionService.sincronizarRecordatorios(proximas);

    if (!mounted) return;
    setState(() {
      _canchas = canchas;
      _complejos = complejos;

      // Si el complejo seleccionado ya no existe, volvemos a "Todos".
      if (_complejoSeleccionadoId != null &&
          !complejos.any((c) => c.id == _complejoSeleccionadoId)) {
        _complejoSeleccionadoId = null;
      }

      _proximas = proximas;
      _esAdmin = admin;
      _nombreUsuario = perfil.datos?.nombre.split(' ').first ?? '';
      _cargando = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Filtros
  // ---------------------------------------------------------------------------

  List<Cancha> get _canchasFiltradas {
    var lista = _canchas;

    if (_complejoSeleccionadoId != null) {
      lista =
          lista.where((c) => c.complejoId == _complejoSeleccionadoId).toList();
    }

    if (_busqueda.trim().isEmpty) return lista;

    final q = _busqueda.toLowerCase();
    return lista
        .where((c) =>
            c.nombre.toLowerCase().contains(q) ||
            c.tipoSuperficie.toLowerCase().contains(q))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Selector de complejos (chips)
  // ---------------------------------------------------------------------------

  Widget _selectorComplejos() {
    if (_complejos.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        itemCount: _complejos.length + 1, // +1 = chip "Todos"
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          if (i == 0) {
            final activo = _complejoSeleccionadoId == null;
            return _chipComplejo(
              titulo: 'Todos',
              subtitulo: '${_canchas.length} canchas',
              icono: Icons.grid_view_rounded,
              seleccionado: activo,
              onTap: () => setState(() => _complejoSeleccionadoId = null),
            );
          }

          final complejo = _complejos[i - 1];
          final activo = _complejoSeleccionadoId == complejo.id;
          final total =
              _canchas.where((c) => c.complejoId == complejo.id).length;

          return _chipComplejo(
            titulo: complejo.nombre,
            subtitulo: total == 1 ? '1 cancha' : '$total canchas',
            icono: Icons.location_on_rounded,
            seleccionado: activo,
            onTap: () =>
                setState(() => _complejoSeleccionadoId = complejo.id),
          );
        },
      ),
    );
  }

  Widget _chipComplejo({
    required String titulo,
    required String subtitulo,
    required IconData icono,
    required bool seleccionado,
    required VoidCallback onTap,
  }) {
    final bg = seleccionado ? AppColors.primary : Colors.white;
    final fg = seleccionado ? Colors.white : AppColors.ink;
    final fgSoft = seleccionado
        ? Colors.white.withValues(alpha: 0.85)
        : AppColors.inkMuted;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppRadius.sm + 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm + 4),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.sm + 4),
            border: Border.all(
              color: seleccionado ? AppColors.primary : AppColors.border,
            ),
            boxShadow: seleccionado ? AppShadows.soft : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icono, size: 18, color: fg),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    titulo,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: fg,
                    ),
                  ),
                  Text(
                    subtitulo,
                    style: TextStyle(fontSize: 11.5, color: fgSoft),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Nueva reserva
  // ---------------------------------------------------------------------------

  void _abrirModalReserva(Cancha cancha) {
    DateTime fecha = DateTime.now();
    TimeOfDay horaInicio = TimeOfDay(
      hour: (DateTime.now().hour + 1).clamp(6, 21),
      minute: 0,
    );
    TimeOfDay horaFin = TimeOfDay(
      hour: (DateTime.now().hour + 2).clamp(7, 22),
      minute: 0,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final minutosInicio = horaInicio.hour * 60 + horaInicio.minute;
          final minutosFin = horaFin.hour * 60 + horaFin.minute;
          final horas = (minutosFin - minutosInicio) / 60;
          final horarioValido = horas > 0;
          final monto = horarioValido ? horas * cancha.precioHora : 0.0;

          final esHoy = fecha.year == DateTime.now().year &&
              fecha.month == DateTime.now().month &&
              fecha.day == DateTime.now().day;
          final ahoraEnMinutos =
              DateTime.now().hour * 60 + DateTime.now().minute;
          final horaEnPasado = esHoy && minutosInicio <= ahoraEnMinutos;

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              top: 12,
              left: 20,
              right: 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                      ),
                      child: const Icon(Icons.stadium_rounded,
                          color: AppColors.primary, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cancha.nombre,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                            ),
                          ),
                          if (cancha.complejoNombre != null &&
                              cancha.complejoNombre!.isNotEmpty)
                            Text(
                              cancha.complejoNombre!,
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.inkMuted),
                            ),
                          Text(
                            '${cancha.tipoSuperficie} · '
                            '${Formato.moneda(cancha.precioHora)}/hora',
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.inkSoft),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                _selectorCampo(
                  icono: Icons.calendar_today_rounded,
                  etiqueta: 'Fecha del partido',
                  valor: Formato.etiquetaDia(fecha),
                  onTap: () async {
                    final elegida = await showDatePicker(
                      context: ctx,
                      initialDate: fecha,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 60)),
                      helpText: 'Elige la fecha',
                      cancelText: 'Cancelar',
                      confirmText: 'Listo',
                    );
                    if (elegida != null) setModalState(() => fecha = elegida);
                  },
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: _selectorCampo(
                        icono: Icons.play_arrow_rounded,
                        etiqueta: 'Desde',
                        valor: horaInicio.format(ctx),
                        onTap: () async {
                          final elegida = await showTimePicker(
                            context: ctx,
                            initialTime: horaInicio,
                            helpText: 'Hora de inicio',
                          );
                          if (elegida != null) {
                            setModalState(() {
                              horaInicio = elegida;
                              if (elegida.hour * 60 + elegida.minute >=
                                  horaFin.hour * 60 + horaFin.minute) {
                                horaFin = TimeOfDay(
                                  hour: (elegida.hour + 1) % 24,
                                  minute: elegida.minute,
                                );
                              }
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _selectorCampo(
                        icono: Icons.stop_rounded,
                        etiqueta: 'Hasta',
                        valor: horaFin.format(ctx),
                        onTap: () async {
                          final elegida = await showTimePicker(
                            context: ctx,
                            initialTime: horaFin,
                            helpText: 'Hora de finalización',
                          );
                          if (elegida != null) {
                            setModalState(() => horaFin = elegida);
                          }
                        },
                      ),
                    ),
                  ],
                ),

                if (!horarioValido) ...[
                  const SizedBox(height: 14),
                  const Aviso(
                    texto:
                        'La hora de finalización debe ser posterior a la de inicio.',
                    icono: Icons.warning_amber_rounded,
                    color: AppColors.warning,
                  ),
                ] else if (horaEnPasado) ...[
                  const SizedBox(height: 14),
                  const Aviso(
                    texto:
                        'Esa hora ya pasó. Elige un horario más adelante o cambia la fecha.',
                    icono: Icons.warning_amber_rounded,
                    color: AppColors.warning,
                  ),
                ],

                const SizedBox(height: 20),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Total a pagar',
                            style: TextStyle(
                                fontSize: 13, color: AppColors.inkSoft),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            horarioValido
                                ? '${Formato.duracion(horas)} × '
                                    '${Formato.moneda(cancha.precioHora)}'
                                : 'Revisa el horario',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.inkMuted),
                          ),
                        ],
                      ),
                      Text(
                        Formato.moneda(monto),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryDark,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (!horarioValido || horaEnPasado)
                        ? null
                        : () => _continuarAlPago(
                              ctx,
                              cancha: cancha,
                              fecha: fecha,
                              horaInicio: horaInicio,
                              horaFin: horaFin,
                              monto: monto,
                            ),
                    icon: const Icon(Icons.lock_outline_rounded, size: 19),
                    label: const Text('CONTINUAR AL PAGO'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _continuarAlPago(
    BuildContext modalContext, {
    required Cancha cancha,
    required DateTime fecha,
    required TimeOfDay horaInicio,
    required TimeOfDay horaFin,
    required double monto,
  }) async {
    String hhmm(TimeOfDay t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    Navigator.pop(modalContext);

    final reservaCreada = await Navigator.push<Reserva>(
      context,
      MaterialPageRoute(
        builder: (_) => PantallaPagoScreen(
          cancha: cancha,
          fecha: Formato.iso(fecha),
          horaInicio: hhmm(horaInicio),
          horaFin: hhmm(horaFin),
          montoTotal: monto,
        ),
      ),
    );

    if (reservaCreada == null || !mounted) return;

    await _cargarTodo();
    if (!mounted) return;

    context.findAncestorStateOfType<MainShellState>()?.reservaCreada();
  }

  // ---------------------------------------------------------------------------
  // Info de la empresa
  // ---------------------------------------------------------------------------

  void _mostrarInfoEmpresa() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                  ),
                  child: const Icon(Icons.business_rounded,
                      color: AppColors.primary, size: 24),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Canchas Ya!',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'Somos la plataforma para gestionar y reservar canchas '
              'sintéticas en minutos. Reserva, paga y recibe recordatorios '
              'antes de tu partido.',
              style: TextStyle(
                  fontSize: 14.5, height: 1.5, color: AppColors.inkSoft),
            ),
            const SizedBox(height: 20),
            const FilaDato(
              icono: Icons.schedule_rounded,
              etiqueta: 'Horario de atención',
              valor: 'Lunes a domingo, 6:00 a 22:00',
            ),
            const FilaDato(
              icono: Icons.phone_rounded,
              etiqueta: 'Teléfono',
              valor: '+502 5692-8129',
            ),
            const FilaDato(
              icono: Icons.location_on_rounded,
              etiqueta: 'Dirección',
              valor: 'zona 12 de Ciudad de Guatemala',
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final saludo = _saludo();
    final proxima = _proximas.isNotEmpty ? _proximas.first : null;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _cargarTodo,
        color: AppColors.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: GradientHeader(
                titulo: _nombreUsuario.isEmpty
                    ? '$saludo 👋'
                    : '$saludo, $_nombreUsuario 👋',
                subtitulo: '¿Listo para el próximo partido?',
                acciones: [
                  if (_esAdmin)
                    HeaderIconButton(
                      icono: Icons.admin_panel_settings_rounded,
                      tooltip: 'Aprobar reservas',
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const AdminReservasScreen()),
                        );
                        if (mounted) _cargarTodo();
                      },
                    ),
                  if (_esAdmin) const SizedBox(width: 8),
                  HeaderIconButton(
                    icono: Icons.info_outline_rounded,
                    tooltip: 'Sobre la empresa',
                    onTap: _mostrarInfoEmpresa,
                  ),
                ],
                contenidoInferior: _buscador(),
              ),
            ),

            // -----------------------------------------------------------------
            // Selector de complejos:
            //   - Si el usuario llegó desde el selector de complejos
            //     (widget.complejo != null), NO mostramos los chips:
            //     ya está filtrando por su complejo.
            //   - Si viene sin complejo (ej. "Todos"), mostramos los chips
            //     para que pueda filtrar manualmente.
            // -----------------------------------------------------------------
            if (widget.complejo == null)
              SliverToBoxAdapter(
                child: _selectorComplejos(),
              ),

            // Próxima reserva destacada
            if (proxima != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: _tarjetaProximaReserva(proxima),
                ),
              ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                child: SeccionTitulo(
                  titulo: 'Canchas disponibles',
                  accionTexto: _canchasFiltradas.isEmpty
                      ? null
                      : '${_canchasFiltradas.length} en total',
                ),
              ),
            ),

            if (_cargando)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Cargando(texto: 'Cargando canchas...'),
                ),
              )
            else if (_canchasFiltradas.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EstadoVacio(
                  icono: _busqueda.isEmpty
                      ? Icons.sentiment_dissatisfied_rounded
                      : Icons.search_off_rounded,
                  titulo: _busqueda.isEmpty
                      ? 'No hay canchas disponibles'
                      : 'Sin resultados',
                  mensaje: _busqueda.isEmpty
                      ? 'No hay canchas en este complejo. Prueba con otro.'
                      : 'No encontramos canchas que coincidan con "$_busqueda".',
                  accionTexto:
                      _busqueda.isEmpty ? 'Ver todas' : 'Limpiar búsqueda',
                  onAccion: () {
                    if (_busqueda.isEmpty) {
                      setState(() => _complejoSeleccionadoId = null);
                    } else {
                      setState(() => _busqueda = '');
                    }
                  },
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                sliver: SliverList.separated(
                  itemCount: _canchasFiltradas.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) =>
                      _tarjetaCancha(_canchasFiltradas[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Widgets auxiliares
  // ---------------------------------------------------------------------------

  Widget _buscador() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.sm + 4),
        boxShadow: AppShadows.soft,
      ),
      child: TextField(
        onChanged: (v) => setState(() => _busqueda = v),
        decoration: InputDecoration(
          hintText: 'Buscar cancha por nombre o tipo...',
          prefixIcon: const Icon(Icons.search_rounded, size: 22),
          suffixIcon: _busqueda.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 19),
                  onPressed: () => setState(() => _busqueda = ''),
                ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }

  Widget _tarjetaProximaReserva(Reserva reserva) {
    final estado = reserva.estadoEfectivo;
    return AppCard(
      padding: EdgeInsets.zero,
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DetalleReservaScreen(reserva: reserva),
          ),
        );
        if (mounted) _cargarTodo();
      },
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: estado.color.withValues(alpha: 0.10),
            child: Row(
              children: [
                Icon(estado.icono, size: 17, color: estado.color),
                const SizedBox(width: 8),
                Text(
                  'Tu próxima reserva',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: estado.color,
                    letterSpacing: 0.2,
                  ),
                ),
                const Spacer(),
                Text(
                  reserva.tiempoRelativo,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: estado.color,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reserva.canchaNombre,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${Formato.etiquetaDia(reserva.inicio)} · '
                        '${reserva.rangoHorario}',
                        style: const TextStyle(
                            fontSize: 13.5, color: AppColors.inkSoft),
                      ),
                    ],
                  ),
                ),
                EstadoChip(estado: estado),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaCancha(Cancha cancha) {
    final disponible = cancha.activa;

    return AppCard(
      padding: EdgeInsets.zero,
      onTap: disponible ? () => _abrirModalReserva(cancha) : null,
      child: Row(
        children: [
          Container(
            width: 76,
            height: 96,
            decoration: BoxDecoration(
              gradient: (cancha.imagenUrl == null || cancha.imagenUrl!.isEmpty)
                  ? (disponible
                      ? AppColors.heroGradient
                      : LinearGradient(colors: [
                          Colors.grey.shade400,
                          Colors.grey.shade500,
                        ]))
                  : null,
            ),
            child: (cancha.imagenUrl != null && cancha.imagenUrl!.isNotEmpty)
                ? ClipRRect(
                    child: Image.network(
                      cancha.imagenUrl!,
                      fit: BoxFit.cover,
                      width: 76,
                      height: 96,
                      color: disponible
                          ? null
                          : Colors.grey.withValues(alpha: 0.5),
                      colorBlendMode:
                          disponible ? null : BlendMode.saturation,
                      errorBuilder: (context, error, stackTrace) => Container(
                        decoration: BoxDecoration(
                          gradient: disponible
                              ? AppColors.heroGradient
                              : LinearGradient(colors: [
                                  Colors.grey.shade400,
                                  Colors.grey.shade500,
                                ]),
                        ),
                        child: const Center(
                          child: Icon(Icons.grass_rounded,
                              color: Colors.white, size: 32),
                        ),
                      ),
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          color: AppColors.background,
                          child: const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      },
                    ),
                  )
                : const Center(
                    child: Icon(Icons.grass_rounded,
                        color: Colors.white, size: 32),
                  ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    cancha.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (cancha.complejoNombre != null &&
                      cancha.complejoNombre!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded,
                            size: 12, color: AppColors.inkMuted),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            cancha.complejoNombre!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11.5, color: AppColors.inkMuted),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (cancha.descripcion?.isNotEmpty == true &&
                      cancha.descripcion!.toLowerCase() !=
                          'sin descripción') ...[
                    const SizedBox(height: 2),
                    Text(
                      cancha.descripcion!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _etiquetaPequena(
                        Icons.layers_outlined,
                        cancha.tipoSuperficie,
                      ),
                      const SizedBox(width: 8),
                      if (!disponible)
                        _etiquetaPequena(
                          Icons.do_not_disturb_on_outlined,
                          'No disponible',
                          color: AppColors.danger,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        Formato.moneda(cancha.precioHora),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryDark,
                        ),
                      ),
                      const Text(
                        ' / hora',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.inkMuted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: disponible
                ? Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: const Row(
                      children: [
                        Text(
                          'Reservar',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(Icons.chevron_right_rounded,
                            color: Colors.white, size: 18),
                      ],
                    ),
                  )
                : const Icon(Icons.lock_outline_rounded,
                    color: AppColors.inkMuted, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _selectorCampo({
    required IconData icono,
    required String etiqueta,
    required String valor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(AppRadius.sm + 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm + 2),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.sm + 2),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(icono, size: 19, color: AppColors.primary),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      etiqueta,
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.inkMuted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      valor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.unfold_more_rounded,
                  size: 17, color: AppColors.inkMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _etiquetaPequena(IconData icono, String texto, {Color? color}) {
    final c = color ?? AppColors.inkSoft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 12, color: c),
          const SizedBox(width: 4),
          Text(
            texto,
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w600, color: c),
          ),
        ],
      ),
    );
  }

  String _saludo() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Buenos días';
    if (h < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }
}