import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/qr_estado.dart';
import '../domain/qr_operacion.dart';
import 'qr_repositorio.dart';

/// Implementación en línea de [QrFuenteDatos]. El servidor (trigger
/// `qr_operaciones_aplicar`) decide el resultado en el mismo INSERT, así que el
/// resultado se lee de la propia fila. La versión offline (cola Drift +
/// PowerSync) cumple el mismo contrato.
class QrSupabase implements QrFuenteDatos {
  QrSupabase(this._db);
  final SupabaseClient _db;

  @override
  Future<QrVista?> buscarPorCodigo(String fincaId, String codigo) async {
    final f = await _db
        .from('codigos_qr')
        .select('codigo, estado, animal_actual_id')
        .eq('finca_id', fincaId)
        .eq('codigo', codigo)
        .eq('is_deleted', false)
        .maybeSingle();
    if (f == null) return null;
    final estado = QrEstado.tryParse(f['estado'] as String?);
    if (estado == null) return null; // estado desconocido: no se adivina
    return QrVista(codigo: f['codigo'] as String, estado: estado, animalActualId: f['animal_actual_id'] as String?);
  }

  @override
  Future<void> encolar(QrSolicitud s) async {
    try {
      await _db.from('qr_operaciones').insert({
        'id': s.id,
        'finca_id': s.fincaId,
        'codigo': s.codigo,
        'operacion': s.tipo.name,
        'animal_id': s.animalId,
        'motivo': s.motivo,
        'estado_esperado': s.estadoEsperado?.name,
        'creada_en': s.creadaEn.toIso8601String(),
      });
    } on PostgrestException catch (e) {
      // 23505 = el mismo id ya fue procesado (reintento): no es error, se lee su resultado.
      if (e.code != '23505') rethrow;
    }
  }

  @override
  Stream<QrResultadoSync> observarResultado(String solicitudId) async* {
    final f = await _db.from('qr_operaciones').select('estado, resultado_detalle').eq('id', solicitudId).maybeSingle();
    if (f == null) {
      yield const QrResultadoSync(QrResultado.pendiente);
      return;
    }
    final d = (f['resultado_detalle'] as Map?) ?? const {};
    yield QrResultadoSync(
      QrResultado.parse(f['estado'] as String?),
      codigoError: d['codigo_error'] as String?,
      mensaje: d['mensaje'] as String?,
    );
  }
}
