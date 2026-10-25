import 'package:flutter/material.dart';

import '../models/reserva_model.dart';
import '../theme/app_theme.dart';

/// Chip de color que muestra el estado de una reserva.
class EstadoChip extends StatelessWidget {
  final EstadoReserva estado;
  final bool compacto;

  const EstadoChip({super.key, required this.estado, this.compacto = false});

  @override
  Widget build(BuildContext context) {
    final color = estado.color;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compacto ? 9 : 12,
        vertical: compacto ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(estado.icono, size: compacto ? 13 : 15, color: color),
          SizedBox(width: compacto ? 4 : 6),
          Text(
            estado.etiquetaCorta,
            style: TextStyle(
              color: color,
              fontSize: compacto ? 11 : 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Encabezado con degradado verde, usado arriba de las pantallas principales.
class GradientHeader extends StatelessWidget {
  final String titulo;
  final String? subtitulo;
  final List<Widget> acciones;
  final Widget? contenidoInferior;
  final bool mostrarAtras;
  final double paddingInferior;

  /// Qué hacer al tocar la flecha de retroceso. Si es null, hace un pop normal.
  final VoidCallback? onAtras;

  const GradientHeader({
    super.key,
    required this.titulo,
    this.subtitulo,
    this.acciones = const [],
    this.contenidoInferior,
    this.mostrarAtras = false,
    this.paddingInferior = 22,
    this.onAtras,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(AppRadius.lg + 6),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: mostrarAtras ? 4 : 20,
            right: 12,
            top: 12,
            bottom: paddingInferior,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (mostrarAtras)
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      onPressed: onAtras ?? () => Navigator.maybePop(context),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titulo,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        if (subtitulo != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitulo!,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 13.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  ...acciones,
                ],
              ),
              if (contenidoInferior != null) ...[
                const SizedBox(height: 18),
                contenidoInferior!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Botón circular translúcido para el encabezado.
class HeaderIconButton extends StatelessWidget {
  final IconData icono;
  final String tooltip;
  final VoidCallback onTap;
  final int? badge;

  const HeaderIconButton({
    super.key,
    required this.icono,
    required this.tooltip,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: Colors.white.withValues(alpha: 0.18),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(icono, color: Colors.white, size: 21),
              ),
            ),
          ),
          if (badge != null && badge! > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 18),
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  shape: badge! > 9 ? BoxShape.rectangle : BoxShape.circle,
                  borderRadius: badge! > 9 ? BorderRadius.circular(9) : null,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text(
                  badge! > 9 ? '9+' : '$badge',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Tarjeta blanca con borde suave, la base visual de la app.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: borderColor ?? AppColors.border),
        boxShadow: AppShadows.soft,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Sección con título y (opcionalmente) una acción a la derecha.
class SeccionTitulo extends StatelessWidget {
  final String titulo;
  final String? accionTexto;
  final VoidCallback? onAccion;

  const SeccionTitulo({
    super.key,
    required this.titulo,
    this.accionTexto,
    this.onAccion,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(titulo, style: Theme.of(context).textTheme.titleLarge),
        if (accionTexto != null)
          TextButton(
            onPressed: onAccion,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
            ),
            child: Row(
              children: [
                Text(accionTexto!, style: const TextStyle(fontSize: 13.5)),
                const Icon(Icons.chevron_right_rounded, size: 18),
              ],
            ),
          ),
      ],
    );
  }
}

/// Mensaje amable cuando una lista está vacía.
class EstadoVacio extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String mensaje;
  final String? accionTexto;
  final VoidCallback? onAccion;

  const EstadoVacio({
    super.key,
    required this.icono,
    required this.titulo,
    required this.mensaje,
    this.accionTexto,
    this.onAccion,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.09),
                shape: BoxShape.circle,
              ),
              child: Icon(icono, size: 42, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.inkSoft,
                height: 1.45,
              ),
            ),
            if (accionTexto != null) ...[
              const SizedBox(height: 22),
              ElevatedButton(onPressed: onAccion, child: Text(accionTexto!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Fila etiqueta / valor para las pantallas de detalle y perfil.
class FilaDato extends StatelessWidget {
  final IconData icono;
  final String etiqueta;
  final String valor;
  final Color? colorValor;
  final Widget? trailing;

  const FilaDato({
    super.key,
    required this.icono,
    required this.etiqueta,
    required this.valor,
    this.colorValor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icono, size: 18, color: AppColors.inkSoft),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  etiqueta,
                  style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  valor.isEmpty ? '—' : valor,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: colorValor ?? AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Aviso de color (informativo, advertencia, error).
class Aviso extends StatelessWidget {
  final String texto;
  final IconData icono;
  final Color color;

  const Aviso({
    super.key,
    required this.texto,
    this.icono = Icons.info_outline_rounded,
    this.color = AppColors.info,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm + 2),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 19, color: color),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: color.withValues(alpha: 0.95),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Muestra un SnackBar con el estilo de la app.
void mostrarMensaje(
  BuildContext context,
  String texto, {
  bool esError = false,
  bool esExito = false,
  Duration duracion = const Duration(seconds: 3),
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      duration: duracion,
      backgroundColor: esError
          ? AppColors.danger
          : esExito
              ? AppColors.primaryDark
              : AppColors.ink,
      content: Row(
        children: [
          Icon(
            esError
                ? Icons.error_outline_rounded
                : esExito
                    ? Icons.check_circle_outline_rounded
                    : Icons.info_outline_rounded,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(texto)),
        ],
      ),
    ),
  );
}

/// Indicador de carga centrado con el color de la app.
class Cargando extends StatelessWidget {
  final String? texto;
  const Cargando({super.key, this.texto});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          if (texto != null) ...[
            const SizedBox(height: 16),
            Text(texto!, style: const TextStyle(color: AppColors.inkSoft)),
          ],
        ],
      ),
    );
  }
}
