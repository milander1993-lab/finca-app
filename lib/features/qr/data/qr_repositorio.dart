import '../domain/qr_estado.dart';
import '../domain/qr_operacion.dart';

/// Acceso a datos del QR. Contrato que la capa de sincronización (Drift +
/// PowerSync) debe implementar; los archivos reales de esa capa no fueron
/// entregados, por eso se declara aquí como interfaz (DT-010).
abstract class QrFuenteDatos {
  /// Lee el QR desde la réplica local. Null si el código no está en el dispositivo.
  Future<QrVista?> buscarPorCodigo(String fincaId, String codigo);

  /// Inserta la solicitud en la bandeja local (`qr_operaciones`); el motor de
  /// sincronización la sube y el servidor escribe el resultado.
  /// Debe ser idempotente por [QrSolicitud.id].
  Future<void> encolar(QrSolicitud s);

  /// Observa el resultado sincronizado de una solicitud.
  Stream<QrResultadoSync> observarResultado(String solicitudId);
}

class QrResultadoSync {
  const QrResultadoSync(this.resultado, {this.codigoError, this.mensaje});
  final QrResultado resultado;
  final String? codigoError;
  final String? mensaje;
}

/// Identificador único generado en el cliente. Se inyecta para poder probarlo.
typedef GeneradorId = String Function();

class QrRepositorio {
  QrRepositorio(this._datos, this._nuevoId, {DateTime Function()? reloj})
      : _reloj = reloj ?? DateTime.now;
  final QrFuenteDatos _datos;
  final GeneradorId _nuevoId;
  final DateTime Function() _reloj;

  Future<QrVista?> consultar(String fincaId, String codigoLeido) async {
    final codigo = normalizarCodigo(codigoLeido);
    if (codigo == null) return null;
    return _datos.buscarPorCodigo(fincaId, codigo);
  }

  /// Valida localmente, encola y devuelve el id de la solicitud para seguir su
  /// resultado. Lanza [QrOperacionInvalida] si no pasa la validación local.
  Future<String> solicitar({
    required String fincaId,
    required String codigoLeido,
    required QrTipoOperacion tipo,
    String? animalId,
    String? motivo,
  }) async {
    final codigo = normalizarCodigo(codigoLeido);
    if (codigo == null) throw const QrOperacionInvalida('Código vacío.');
    final vista = await _datos.buscarPorCodigo(fincaId, codigo);
    final v = validarLocal(tipo: tipo, vista: vista, animalId: animalId, motivo: motivo);
    if (!v.esValida) throw QrOperacionInvalida(v.error!);

    final s = QrSolicitud(
      id: _nuevoId(),
      fincaId: fincaId,
      codigo: codigo,
      tipo: tipo,
      creadaEn: _reloj().toUtc(),
      animalId: animalId,
      motivo: motivo?.trim(),
      estadoEsperado: vista?.estado,
    );
    await _datos.encolar(s);
    return s.id;
  }

  Stream<QrResultadoSync> seguir(String solicitudId) => _datos.observarResultado(solicitudId);
}

class QrOperacionInvalida implements Exception {
  const QrOperacionInvalida(this.mensaje);
  final String mensaje;
  @override
  String toString() => mensaje;
}
