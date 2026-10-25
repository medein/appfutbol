import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/complejo_model.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';

/// Pantalla de inicio: el usuario elige el complejo donde quiere jugar.
/// Al tocar un complejo se llama a [onSeleccionar]; ahí decides qué mostrar
/// (normalmente la pantalla de canchas de ese complejo).
class ComplejosScreen extends StatefulWidget {
  final void Function(Complejo complejo) onSeleccionar;

  /// Complejo elegido antes (se marca en la lista). Opcional.
  final int? complejoActualId;

  const ComplejosScreen({
    super.key,
    required this.onSeleccionar,
    this.complejoActualId,
  });

  @override
  State<ComplejosScreen> createState() => _ComplejosScreenState();
}

class _ComplejosScreenState extends State<ComplejosScreen> {
  List<Complejo> _complejos = [];
  bool _cargando = true;
  bool _buscandoUbicacion = false;
  bool _ordenadoPorCercania = false;
  String? _error;
  Position? _posicion;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    final res = await ApiService.getComplejos(
      latitud: _posicion?.latitude,
      longitud: _posicion?.longitude,
    );

    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (res.exito) {
        _complejos = res.datos ?? [];
        _ordenadoPorCercania = _posicion != null;
      } else {
        _error = res.mensaje;
      }
    });
  }

  /// Pide permiso de ubicación y recarga los complejos ordenados por cercanía.
  Future<void> _ordenarPorCercania() async {
    if (_buscandoUbicacion) return;
    setState(() => _buscandoUbicacion = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          mostrarMensaje(context, 'Activa el GPS del dispositivo.');
        }
        return;
      }
      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }
      if (permiso == LocationPermission.denied ||
          permiso == LocationPermission.deniedForever) {
        if (mounted) {
          mostrarMensaje(context, 'Sin permiso de ubicación.');
        }
        return;
      }
      _posicion = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
      await _cargar();
    } catch (e) {
      if (mounted) {
        mostrarMensaje(context, 'No pude obtener tu ubicación.');
      }
    } finally {
      if (mounted) setState(() => _buscandoUbicacion = false);
    }
  }

  Future<void> _elegir(Complejo complejo) async {
    await ApiService.guardarComplejo(complejo);
    if (!mounted) return;
    widget.onSeleccionar(complejo);
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          GradientHeader(
            titulo: 'Elige tu complejo',
            subtitulo: _ordenadoPorCercania
                ? 'Ordenados del más cercano al más lejano'
                : '¿Dónde quieres jugar?',
            acciones: [
              HeaderIconButton(
                icono: _ordenadoPorCercania
                    ? Icons.location_on_rounded
                    : Icons.my_location_rounded,
                tooltip: 'Ver el complejo más cercano',
                onTap: _ordenarPorCercania,
              ),
              HeaderIconButton(
                icono: Icons.refresh_rounded,
                tooltip: 'Actualizar',
                onTap: _cargar,
              ),
            ],
            paddingInferior: 18,
          ),
          Expanded(child: _contenido()),
        ],
      ),
    );
  }

  Widget _contenido() {
    if (_cargando) return const Cargando(texto: 'Buscando complejos...');

    if (_error != null) {
      return _mensajeCentral(
        icono: Icons.wifi_off_rounded,
        titulo: 'No pudimos cargar los complejos',
        detalle: _error!,
        boton: 'Reintentar',
      );
    }

    if (_complejos.isEmpty) {
      return _mensajeCentral(
        icono: Icons.location_off_rounded,
        titulo: 'Aún no hay complejos registrados',
        detalle: 'Vuelve a intentarlo en unos minutos.',
        boton: 'Actualizar',
      );
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        itemCount: _complejos.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (context, i) => _tarjetaComplejo(_complejos[i], i),
      ),
    );
  }

  Widget _mensajeCentral({
    required IconData icono,
    required String titulo,
    required String detalle,
    required String boton,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 48, color: AppColors.inkMuted),
            const SizedBox(height: 14),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detalle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5, color: AppColors.inkSoft),
            ),
            const SizedBox(height: 18),
            OutlinedButton(onPressed: _cargar, child: Text(boton)),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaComplejo(Complejo complejo, int indice) {
    final esActual = complejo.id == widget.complejoActualId;
    final foto = ApiService.urlAbsoluta(complejo.imagenUrl);
    final esElMasCercano = _ordenadoPorCercania &&
        indice == 0 &&
        complejo.distanciaKm != null;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => _elegir(complejo),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: esActual ? AppColors.primary : AppColors.border,
              width: esActual ? 1.8 : 1,
            ),
            boxShadow: AppShadows.soft,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  SizedBox(
                    height: 130,
                    width: double.infinity,
                    child: foto == null
                        ? _fotoVacia()
                        : Image.network(
                            foto,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _fotoVacia(),
                          ),
                  ),
                  if (esElMasCercano)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: _etiqueta('El más cercano', AppColors.primary,
                          Colors.white),
                    ),
                  if (esActual)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: _etiqueta(
                          'Tu complejo', Colors.white, AppColors.primary),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      complejo.nombre,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    if (complejo.direccion != null &&
                        complejo.direccion!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 1),
                            child: Icon(Icons.place_outlined,
                                size: 15, color: AppColors.inkMuted),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              complejo.direccion!,
                              style: const TextStyle(
                                  fontSize: 13, color: AppColors.inkSoft),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _dato(Icons.sports_soccer_rounded,
                            '${complejo.totalCanchas} '
                            '${complejo.totalCanchas == 1 ? 'cancha' : 'canchas'}'),
                        if (complejo.precioDesde != null)
                          _dato(Icons.payments_outlined,
                              'Desde Q${complejo.precioDesde!.toStringAsFixed(0)}/h'),
                        if (complejo.horario != null)
                          _dato(Icons.schedule_rounded, complejo.horario!),
                        if (complejo.calificacion != null &&
                            complejo.calificacion! > 0)
                          _dato(Icons.star_rounded,
                              complejo.calificacion!.toStringAsFixed(1)),
                        if (complejo.distanciaKm != null)
                          _dato(Icons.near_me_rounded,
                              '${complejo.distanciaKm!.toStringAsFixed(1)} km'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fotoVacia() {
    return Container(
      color: AppColors.primary.withValues(alpha: 0.10),
      child: const Center(
        child: Icon(Icons.stadium_rounded, size: 44, color: AppColors.primary),
      ),
    );
  }

  Widget _etiqueta(String texto, Color fondo, Color colorTexto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: colorTexto,
        ),
      ),
    );
  }

  Widget _dato(IconData icono, String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 14, color: AppColors.primary),
          const SizedBox(width: 5),
          Text(
            texto,
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.ink),
          ),
        ],
      ),
    );
  }
}