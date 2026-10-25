"""Pone la base de datos MySQL al día con lo que necesita la app Flutter.

`Base.metadata.create_all()` solo crea tablas que faltan: NO agrega columnas ni
arregla índices de una tabla que ya existe. Por eso eso se hace aquí.

El script se puede correr todas las veces que quieras: antes de tocar algo
revisa si ya está hecho, así que no falla ni duplica nada.

    venv\\Scripts\\python.exe migrate.py
"""

from sqlalchemy import text
from app.database import engine

# Estados en los que una reserva sigue ocupando el horario.
ESTADOS_OCUPAN = ("pendiente", "confirmada", "completada")

# (tabla, columna, definición SQL)
COLUMNAS = [
    ("usuarios", "direccion", "VARCHAR(255) NULL"),
    ("usuarios", "fecha_nacimiento", "DATE NULL"),
    ("reservas", "comprobante_url", "VARCHAR(255) NULL"),
    ("reservas", "referencia_pago", "VARCHAR(50) NULL"),
]

# Columna calculada por MySQL: vale la hora de inicio mientras la reserva está
# viva y NULL cuando se cancela o se rechaza. Como un índice UNIQUE considera
# distintos todos los NULL, el horario vuelve a quedar libre automáticamente.
LISTA_ESTADOS_SQL = ", ".join(f"'{e}'" for e in ESTADOS_OCUPAN)
SLOT_ACTIVO_DEF = (
    "TIME GENERATED ALWAYS AS ("
    f"CASE WHEN LOWER(estado) IN ({LISTA_ESTADOS_SQL}) "
    "THEN hora_inicio ELSE NULL END) STORED"
)


def columna_existe(cx, tabla: str, columna: str) -> bool:
    return bool(cx.execute(
        text("""
            SELECT COUNT(*) FROM information_schema.columns
            WHERE table_schema = DATABASE()
              AND table_name = :tabla AND column_name = :columna
        """),
        {"tabla": tabla, "columna": columna},
    ).scalar())


def indice_existe(cx, tabla: str, indice: str) -> bool:
    return bool(cx.execute(
        text("""
            SELECT COUNT(*) FROM information_schema.statistics
            WHERE table_schema = DATABASE()
              AND table_name = :tabla AND index_name = :indice
        """),
        {"tabla": tabla, "indice": indice},
    ).scalar())


def agregar_columnas(cx) -> None:
    print("\n[1/2] Columnas nuevas")
    for tabla, columna, definicion in COLUMNAS:
        if columna_existe(cx, tabla, columna):
            print(f"  ya existe   {tabla}.{columna}")
            continue
        cx.execute(text(f"ALTER TABLE {tabla} ADD COLUMN {columna} {definicion}"))
        print(f"  AGREGADA    {tabla}.{columna}")


def arreglar_indice_horarios(cx) -> None:
    """Cambia uq_cancha_horario por uno que no bloquee horarios cancelados.

    El índice original era UNIQUE (cancha_id, fecha_reserva, hora_inicio). Eso
    provocaba dos problemas:

      1. Si una reserva se cancelaba o se rechazaba, ese horario quedaba
         bloqueado para siempre y la API devolvía un error 500 al intentar
         reservarlo de nuevo.
      2. Nunca detectó los solapamientos parciales (una reserva de 18:00 a
         21:00 contra otra de 19:00 a 20:00 tienen distinta hora_inicio).

    El reemplazo usa la columna calculada `slot_activo`, que se vuelve NULL en
    cuanto la reserva se cancela.
    """
    print("\n[2/2] Índice de horarios ocupados")

    if not columna_existe(cx, "reservas", "slot_activo"):
        cx.execute(text(f"ALTER TABLE reservas ADD COLUMN slot_activo {SLOT_ACTIVO_DEF}"))
        print("  AGREGADA    reservas.slot_activo (columna calculada)")
    else:
        print("  ya existe   reservas.slot_activo")

    duplicados = list(cx.execute(text("""
        SELECT cancha_id, fecha_reserva, slot_activo, COUNT(*) AS veces
        FROM reservas
        WHERE slot_activo IS NOT NULL
        GROUP BY cancha_id, fecha_reserva, slot_activo
        HAVING veces > 1
    """)))

    if duplicados:
        print("  AVISO: hay horarios duplicados entre reservas activas.")
        print("         No se puede crear el índice hasta resolverlos a mano:")
        for cancha_id, fecha, hora, veces in duplicados:
            print(f"           cancha {cancha_id}  {fecha}  {hora}  ({veces} reservas)")
        return

    if indice_existe(cx, "reservas", "uq_cancha_horario"):
        cx.execute(text("ALTER TABLE reservas DROP INDEX uq_cancha_horario"))
        print("  ELIMINADO   uq_cancha_horario (bloqueaba los horarios cancelados)")
    else:
        print("  ya no está  uq_cancha_horario")

    if not indice_existe(cx, "reservas", "uq_cancha_slot_activo"):
        cx.execute(text("""
            ALTER TABLE reservas
            ADD UNIQUE KEY uq_cancha_slot_activo (cancha_id, fecha_reserva, slot_activo)
        """))
        print("  CREADO      uq_cancha_slot_activo (ignora canceladas y rechazadas)")
    else:
        print("  ya existe   uq_cancha_slot_activo")


if __name__ == "__main__":
    print("Migrando la base de datos canchas_reservas...")
    with engine.begin() as conexion:
        agregar_columnas(conexion)
        arreglar_indice_horarios(conexion)
    print("\nListo. La base de datos ya está al día con la API.")
