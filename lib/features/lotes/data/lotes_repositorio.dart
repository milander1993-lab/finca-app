import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/finca_actual.dart';
import '../../../core/supabase.dart';

class Lote {
  const Lote(this.id, this.nombre, this.estado, {this.animales = 0});
  final String id;
  final String nombre;
  final String estado;
  final int animales; // animales con pertenencia abierta
}

class PertenenciaLote {
  const PertenenciaLote(this.loteId, this.loteNombre, this.desde, this.hasta, this.motivoSalida);
  final String loteId;
  final String loteNombre;
  final DateTime desde;
  final DateTime? hasta;
  final String? motivoSalida;
}

abstract class LotesRepositorio {
  Future<List<Lote>> listar(String fincaId);
  Future<void> crear(String fincaId, String nombre);
  Future<List<PertenenciaLote>> historialAnimal(String animalId);
  /// Mueve el animal al lote: cierra la pertenencia abierta (con motivo) y abre la nueva,
  /// en una sola transacción en el servidor (RPC `mover_animal_lote`).
  Future<void> moverAnimal({required String fincaId, required String animalId, required String loteId, required DateTime fecha, required String motivo});
}

class LotesSupabase implements LotesRepositorio {
  LotesSupabase(this._db);
  final SupabaseClient _db;

  @override
  Future<List<Lote>> listar(String fincaId) async {
    final lotes = await _db.from('lotes_ganaderos').select('id, nombre, estado').eq('finca_id', fincaId).eq('is_deleted', false).order('nombre');
    final abiertas = await _db.from('animal_lote').select('lote_id').eq('finca_id', fincaId).eq('is_deleted', false).isFilter('fecha_salida', null);
    final conteo = <String, int>{};
    for (final a in abiertas) {
      final id = a['lote_id'] as String;
      conteo[id] = (conteo[id] ?? 0) + 1;
    }
    return [for (final l in lotes) Lote(l['id'] as String, l['nombre'] as String, l['estado'] as String, animales: conteo[l['id']] ?? 0)];
  }

  @override
  Future<void> crear(String fincaId, String nombre) =>
      _db.from('lotes_ganaderos').insert({'id': nuevoId(), 'finca_id': fincaId, 'nombre': nombre.trim()});

  @override
  Future<List<PertenenciaLote>> historialAnimal(String animalId) async {
    final filas = await _db
        .from('animal_lote')
        .select('lote_id, fecha_ingreso, fecha_salida, motivo_salida, lotes_ganaderos(nombre)')
        .eq('animal_id', animalId)
        .eq('is_deleted', false)
        .order('fecha_ingreso', ascending: false);
    return [
      for (final f in filas)
        PertenenciaLote(
          f['lote_id'] as String,
          (f['lotes_ganaderos'] as Map?)?['nombre'] as String? ?? '—',
          DateTime.parse(f['fecha_ingreso'] as String),
          f['fecha_salida'] == null ? null : DateTime.parse(f['fecha_salida'] as String),
          f['motivo_salida'] as String?,
        )
    ];
  }

  @override
  Future<void> moverAnimal({required String fincaId, required String animalId, required String loteId, required DateTime fecha, required String motivo}) =>
      _db.rpc('mover_animal_lote', params: {
        'p_finca': fincaId,
        'p_animal': animalId,
        'p_lote': loteId,
        'p_fecha': fecha.toUtc().toIso8601String(),
        'p_motivo': motivo,
      });
}

final lotesRepoProvider = Provider<LotesRepositorio>((ref) => LotesSupabase(ref.watch(supabaseProvider)));

final lotesProvider = FutureProvider<List<Lote>>((ref) async {
  final finca = ref.watch(fincaActualProvider);
  if (finca == null) return const [];
  return ref.watch(lotesRepoProvider).listar(finca.id);
});

final historialLoteProvider = FutureProvider.family<List<PertenenciaLote>, String>(
  (ref, animalId) => ref.watch(lotesRepoProvider).historialAnimal(animalId),
);
