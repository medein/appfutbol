import 'package:app_futbol/models/reserva_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fecha en formato yyyy-MM-dd desplazada N días desde hoy.
String fechaRelativa(int dias) {
  final f = DateTime.now().add(Duration(days: dias));
  return '${f.year}-${f.month.toString().padLeft(2, '0')}-'
      '${f.day.toString().padLeft(2, '0')}';
}

Reserva construir({
  int id = 1,
  String? fecha,
  String horaInicio = '14:00:00',
  String horaFin = '15:00:00',
  EstadoReserva estado = EstadoReserva.confirmada,
  MetodoPago metodoPago = MetodoPago.tarjeta,
}) {
  return Reserva(
    id: id,
    canchaId: 1,
    canchaNombre: 'Cancha Norte',
    fecha: fecha ?? fechaRelativa(3),
    horaInicio: horaInicio,
    horaFin: horaFin,
    montoTotal: 250,
    estado: estado,
    metodoPago: metodoPago,
  );
}

void main() {
  group('EstadoReserva', () {
    test('mapea los textos del backend a estados tipados', () {
      expect(EstadoReserva.desdeTexto('confirmada'), EstadoReserva.confirmada);
      expect(EstadoReserva.desdeTexto('APROBADO'), EstadoReserva.confirmada);
      expect(EstadoReserva.desdeTexto('pagado'), EstadoReserva.confirmada);
      expect(EstadoReserva.desdeTexto('rechazada'), EstadoReserva.rechazada);
      expect(EstadoReserva.desdeTexto('finalizada'), EstadoReserva.completada);
      expect(EstadoReserva.desdeTexto('cancelado'), EstadoReserva.cancelada);
      expect(EstadoReserva.desdeTexto('en_revision'), EstadoReserva.pendiente);
      // Cualquier valor desconocido o vacío cae en pendiente.
      expect(EstadoReserva.desdeTexto(null), EstadoReserva.pendiente);
      expect(EstadoReserva.desdeTexto('algo raro'), EstadoReserva.pendiente);
    });

    test('pendiente y confirmada son estados activos; el resto, cerrados', () {
      expect(EstadoReserva.pendiente.esActivo, isTrue);
      expect(EstadoReserva.confirmada.esActivo, isTrue);
      expect(EstadoReserva.completada.esCerrado, isTrue);
      expect(EstadoReserva.cancelada.esCerrado, isTrue);
      expect(EstadoReserva.rechazada.esCerrado, isTrue);
    });
  });

  group('MetodoPago', () {
    test('la tarjeta confirma al instante', () {
      expect(MetodoPago.tarjeta.estadoInicial, EstadoReserva.confirmada);
    });

    test('la transferencia queda pendiente de aprobación', () {
      expect(
          MetodoPago.transferencia.estadoInicial, EstadoReserva.pendiente);
    });

    test('reconoce los alias del backend', () {
      expect(MetodoPago.desdeTexto('credito'), MetodoPago.tarjeta);
      expect(MetodoPago.desdeTexto('deposito'), MetodoPago.transferencia);
      expect(MetodoPago.desdeTexto('cash'), MetodoPago.efectivo);
    });
  });

  group('Reserva.fromJson', () {
    test('lee los campos que envía el backend FastAPI', () {
      final reserva = Reserva.fromJson({
        'id': 7,
        'cancha_id': 3,
        'cancha': {'nombre': 'Cancha Sur'},
        'fecha_reserva': '2026-10-01',
        'hora_inicio': '18:00:00',
        'hora_fin': '19:30:00',
        'precio_total': 375.5,
        'estado': 'pendiente',
        'metodo_pago': 'transferencia',
        'notas': 'Llevamos balón',
      });

      expect(reserva.id, 7);
      expect(reserva.canchaNombre, 'Cancha Sur');
      expect(reserva.fecha, '2026-10-01');
      expect(reserva.montoTotal, 375.5);
      expect(reserva.estado, EstadoReserva.pendiente);
      expect(reserva.metodoPago, MetodoPago.transferencia);
      expect(reserva.horasReservadas, 1.5);
      expect(reserva.rangoHorario, '18:00 - 19:30');
    });

    test('tolera fechas con hora y horas sin segundos', () {
      final reserva = Reserva.fromJson({
        'id': 1,
        'cancha_id': 1,
        'fecha_reserva': '2026-10-01T00:00:00',
        'hora_inicio': '08:00',
        'hora_fin': '2026-10-01T09:00:00',
      });

      expect(reserva.fecha, '2026-10-01');
      expect(reserva.rangoHorario, '08:00 - 09:00');
    });

    test('usa valores por defecto seguros si faltan campos', () {
      final reserva = Reserva.fromJson({'cancha_id': 4});
      expect(reserva.id, 0);
      expect(reserva.canchaNombre, 'Cancha #4');
      expect(reserva.montoTotal, 0.0);
      expect(reserva.estado, EstadoReserva.pendiente);
    });
  });

  group('Clasificación de reservas', () {
    test('una confirmada futura es próxima y admite recordatorio', () {
      final reserva = construir(fecha: fechaRelativa(2));
      expect(reserva.yaPaso, isFalse);
      expect(reserva.esProxima, isTrue);
      expect(reserva.admiteRecordatorio, isTrue);
      expect(reserva.sePuedeCancelar, isTrue);
    });

    test('una confirmada cuya hora ya pasó se muestra como completada', () {
      final reserva = construir(fecha: fechaRelativa(-5));
      expect(reserva.yaPaso, isTrue);
      expect(reserva.estadoEfectivo, EstadoReserva.completada);
      expect(reserva.esProxima, isFalse);
      // Ya no tiene sentido recordarla ni cancelarla.
      expect(reserva.admiteRecordatorio, isFalse);
      expect(reserva.sePuedeCancelar, isFalse);
    });

    test('una pendiente futura espera aprobación y no genera recordatorio', () {
      final reserva = construir(
        fecha: fechaRelativa(4),
        estado: EstadoReserva.pendiente,
        metodoPago: MetodoPago.transferencia,
      );
      expect(reserva.esperandoAprobacion, isTrue);
      expect(reserva.esProxima, isTrue);
      // El recordatorio solo se programa cuando el pago está confirmado.
      expect(reserva.admiteRecordatorio, isFalse);
    });

    test('una cancelada no es próxima ni cancelable', () {
      final reserva =
          construir(fecha: fechaRelativa(3), estado: EstadoReserva.cancelada);
      expect(reserva.esProxima, isFalse);
      expect(reserva.sePuedeCancelar, isFalse);
      expect(reserva.estadoEfectivo.esCerrado, isTrue);
    });
  });

  group('Utilidades', () {
    test('inicio combina la fecha con la hora', () {
      final reserva = construir(fecha: '2026-10-01', horaInicio: '16:30:00');
      expect(reserva.inicio, DateTime(2026, 10, 1, 16, 30));
    });

    test('horaIgual ignora los segundos', () {
      expect(Reserva.horaIgual('14:00', '14:00:00'), isTrue);
      expect(Reserva.horaIgual('9:00', '09:00:00'), isTrue);
      expect(Reserva.horaIgual('14:00', '15:00:00'), isFalse);
    });

    test('toJson y fromJson conservan la información (ida y vuelta)', () {
      final original = construir(
        id: 42,
        fecha: '2026-11-20',
        estado: EstadoReserva.pendiente,
        metodoPago: MetodoPago.transferencia,
      );
      final copia = Reserva.fromJson(original.toJson());

      expect(copia.id, original.id);
      expect(copia.fecha, original.fecha);
      expect(copia.estado, original.estado);
      expect(copia.metodoPago, original.metodoPago);
      expect(copia.montoTotal, original.montoTotal);
      expect(copia.canchaNombre, original.canchaNombre);
    });

    test('copyWith con null conserva el valor actual', () {
      final reserva = construir(estado: EstadoReserva.pendiente);
      final igual = reserva.copyWith();
      expect(igual.estado, EstadoReserva.pendiente);

      final cambiada = reserva.copyWith(estado: EstadoReserva.confirmada);
      expect(cambiada.estado, EstadoReserva.confirmada);
      expect(cambiada.id, reserva.id);
    });
  });
}
