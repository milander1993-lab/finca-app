import 'qr_estado.dart';

/// Operaciones que el cliente puede solicitar. El servidor decide el resultado.
enum QrTipoOperacion { registrar, asignar, confirmar, liberar, habilitar }

/// Resultado de una operación una vez sincronizada.
enum QrResultado {
  pendiente, // en cola local o aún sin respuesta del servidor
  aplicada,
  rechazada, // viola una regla con el estado actual del servidor
  conflicto; // vista desactualizada: NO se aplicó, espera revisión humana (D-026)

  static QrResultado parse(String? v) => QrResultado.values
      .firstWhere((e) => e.name == v, orElse: () => QrResultado.pendiente);
}

/// Vista local de un QR (réplica de `codigos_qr`).
class QrVista {
  const QrVista({
    required this.codigo,
    required this.estado,
    this.animalActualId,
  });
  final String codigo;
  final QrEstado estado;
  final String? animalActualId;
}

/// Solicitud de operación. El [id] lo genera el cliente (UUID v4): reintentar
/// con el mismo id nunca duplica la operación en el servidor.
class QrSolicitud {
  const QrSolicitud({
    required this.id,
    required this.fincaId,
    required this.codigo,
    required this.tipo,
    required this.creadaEn,
    this.animalId,
    this.motivo,
    this.estadoEsperado,
  });
  final String id;
  final String fincaId;
  final String codigo;
  final QrTipoOperacion tipo;
  final DateTime creadaEn; // hora del evento en el dispositivo
  final String? animalId;
  final String? motivo;

  /// Estado que el dispositivo creía que tenía el QR al operar. Si el servidor
  /// tiene otro, responde `conflicto` en lugar de aplicar (no hay "última
  /// escritura gana" en datos críticos).
  final QrEstado? estadoEsperado;
}

/// Resultado de validar localmente ANTES de encolar. No reemplaza al servidor.
class QrValidacion {
  const QrValidacion.ok() : error = null;
  const QrValidacion.error(this.error);
  final String? error;
  bool get esValida => error == null;
}

/// Validaciones de réplica local: dan retroalimentación inmediata sin red.
/// Cubren solo lo que el dispositivo puede saber; lo demás lo decide el servidor.
QrValidacion validarLocal({
  required QrTipoOperacion tipo,
  required QrVista? vista,
  String? animalId,
  String? motivo,
}) {
  switch (tipo) {
    case QrTipoOperacion.registrar:
      if (vista != null) return const QrValidacion.error('Este código ya está registrado.');
    case QrTipoOperacion.asignar:
      if (animalId == null) return const QrValidacion.error('Seleccione un animal.');
      if (vista == null) return const QrValidacion.error('El código no está registrado.');
      if (vista.estado != QrEstado.disponible) {
        return QrValidacion.error('El QR está "${vista.estado.name}"; solo se asigna uno disponible.');
      }
    case QrTipoOperacion.confirmar:
      if (vista?.estado != QrEstado.asignado) {
        return const QrValidacion.error('Solo se confirma un QR asignado.');
      }
    case QrTipoOperacion.liberar:
      if (vista == null || !vista.estado.tieneAnimal) {
        return const QrValidacion.error('El QR no está asignado a ningún animal.');
      }
      if ((motivo ?? '').trim().isEmpty) {
        return const QrValidacion.error('Indique el motivo de la liberación.');
      }
    case QrTipoOperacion.habilitar:
      if (vista?.estado != QrEstado.liberado) {
        return const QrValidacion.error('Solo se habilita un QR liberado.');
      }
  }
  return const QrValidacion.ok();
}

/// Normaliza el texto leído por la cámara. Devuelve null si queda vacío.
/// No inventa formato: solo recorta espacios y saltos de línea.
String? normalizarCodigo(String? leido) {
  final c = leido?.trim();
  return (c == null || c.isEmpty) ? null : c;
}
