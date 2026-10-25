import 'package:flutter/material.dart';

import '../models/reserva_model.dart';
import '../theme/app_theme.dart';
import '../utils/formato.dart';
import 'app_widgets.dart';

/// Tarjeta de una reserva: fecha grande a la izquierda, datos al centro y
/// el estado arriba a la derecha.
class ReservaCard extends StatelessWidget {
  final Reserva reserva;
  final VoidCallback? onTap;
  final VoidCallback? onCancelar;
  final bool mostrarUsuario;

  const ReservaCard({
    super.key,
    required this.reserva,
    this.onTap,
    this.onCancelar,
    this.mostrarUsuario = false,
  });

  @override
  Widget build(BuildContext context) {
    final estado = reserva.estadoEfectivo;
    final inicio = reserva.inicio;

    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Franja de color según el estado.
          Container(height: 4, color: estado.color.withValues(alpha: 0.85)),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _bloqueFecha(inicio, estado),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            reserva.canchaNombre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _lineaIcono(
                            Icons.schedule_rounded,
                            '${reserva.rangoHorario}  ·  '
                            '${Formato.duracion(reserva.horasReservadas)}',
                          ),
                          const SizedBox(height: 4),
                          _lineaIcono(
                            reserva.metodoPago.icono,
                            reserva.metodoPago == MetodoPago.tarjeta
                                ? 'Pagado con tarjeta'
                                : reserva.metodoPago == MetodoPago.transferencia
                                    ? 'Transferencia / depósito'
                                    : 'Efectivo',
                          ),
                          if (mostrarUsuario &&
                              (reserva.usuarioNombre ?? '').isNotEmpty) ...[
                            const SizedBox(height: 4),
                            _lineaIcono(
                                Icons.person_outline_rounded, reserva.usuarioNombre!),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        EstadoChip(estado: estado, compacto: true),
                        const SizedBox(height: 10),
                        Text(
                          Formato.moneda(reserva.montoTotal),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Aviso de "faltan X" para las reservas confirmadas próximas.
                if (reserva.esProxima) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                    decoration: BoxDecoration(
                      color: estado.color.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          estado == EstadoReserva.pendiente
                              ? Icons.hourglass_top_rounded
                              : Icons.notifications_active_outlined,
                          size: 16,
                          color: estado.color,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            estado == EstadoReserva.pendiente
                                ? 'Esperando que el administrador confirme tu depósito'
                                : 'Te avisaremos antes del partido · '
                                    '${reserva.tiempoRelativo}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: estado.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (onCancelar != null && reserva.sePuedeCancelar) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: onCancelar,
                        icon: const Icon(Icons.close_rounded, size: 17),
                        label: const Text('Cancelar reserva'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          minimumSize: const Size(0, 34),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bloqueFecha(DateTime? inicio, EstadoReserva estado) {
    return Container(
      width: 58,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: estado.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.sm + 2),
      ),
      child: Column(
        children: [
          Text(
            inicio == null ? '—' : Formato.diasCortos[inicio.weekday - 1],
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: estado.color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            inicio == null ? '--' : '${inicio.day}',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.1,
              color: estado.color,
            ),
          ),
          Text(
            inicio == null ? '' : Formato.mesesCortos[inicio.month - 1],
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: estado.color.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineaIcono(IconData icono, String texto) {
    return Row(
      children: [
        Icon(icono, size: 14, color: AppColors.inkMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
          ),
        ),
      ],
    );
  }
}
