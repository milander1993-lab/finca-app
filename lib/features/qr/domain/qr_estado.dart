/// Estados del QR reutilizable (DA-007). Réplica EXACTA de la máquina de estados
/// del servidor (trigger `qr_transicion_valida`, migración 00002). Si se cambia
/// aquí, hay que cambiar allí: el servidor siempre tiene la última palabra.
///
/// DT-009: `asignado` = vinculado a un animal en el sistema, chapa aún sin
/// confirmar; `activo` = vinculación confirmada en campo.
enum QrEstado {
  disponible,
  asignado,
  activo,
  liberado;

  static QrEstado? tryParse(String? valor) {
    for (final e in QrEstado.values) {
      if (e.name == valor) return e;
    }
    return null; // estado desconocido => nunca se adivina
  }

  /// Transiciones permitidas desde este estado.
  Set<QrEstado> get destinos => switch (this) {
        QrEstado.disponible => {QrEstado.asignado},
        QrEstado.asignado => {QrEstado.activo, QrEstado.liberado},
        QrEstado.activo => {QrEstado.liberado},
        QrEstado.liberado => {QrEstado.disponible},
      };

  bool puedePasarA(QrEstado destino) => destinos.contains(destino);

  /// Tiene un animal vinculado.
  bool get tieneAnimal => this == asignado || this == activo;
}
