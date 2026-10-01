import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/finca_actual.dart';
import '../../../core/supabase.dart';
import '../domain/animal.dart';

/// Contrato de datos (DT-010). Implementación actual: Supabase en línea.
/// La implementación offline (Drift + PowerSync) cumple el mismo contrato.
abstract class AnimalesRepositorio {
  Future<List<Animal>> listar(String fincaId);
  Future<Animal> obtener(String id);
  Future<void> crear({required String fincaId, required String numeroInterno, String? categoria, String? sexo, String? estado});
  Future<void> anular(String id);
  Future<List<Pesaje>> pesajes(String animalId);
  Future<void> registrarPesaje({
    required String fincaId,
    required String animalId,
    required DateTime fecha,
    required num valorKg,
    required String naturaleza,
    String? metodo,
    String? observaciones,
  });
}

class AnimalesSupabase implements AnimalesRepositorio {
  AnimalesSupabase(this._db);
  final SupabaseClient _db;

  @override
  Future<List<Animal>> listar(String fincaId) async {
    final filas = await _db.from('animales').select().eq('finca_id', fincaId).eq('is_deleted', false).order('numero_interno');
    return [for (final f in filas) Animal.desdeMapa(f)];
  }

  @override
  Future<Animal> obtener(String id) async => Animal.desdeMapa(await _db.from('animales').select().eq('id', id).single());

  @override
  Future<void> crear({required String fincaId, required String numeroInterno, String? categoria, String? sexo, String? estado}) =>
      _db.from('animales').insert({
        'id': nuevoId(),
        'finca_id': fincaId,
        'numero_interno': numeroInterno.trim(),
        'categoria': _texto(categoria),
        'sexo': _texto(sexo),
        'estado': _texto(estado) ?? 'activo',
      });

  @override
  Future<void> anular(String id) => _db.from('animales').update({'is_deleted': true}).eq('id', id);

  @override
  Future<List<Pesaje>> pesajes(String animalId) async {
    final filas = await _db.from('pesajes').select().eq('animal_id', animalId).eq('is_deleted', false).order('fecha_pesaje', ascending: false);
    return [for (final f in filas) Pesaje.desdeMapa(f)];
  }

  @override
  Future<void> registrarPesaje({
    required String fincaId,
    required String animalId,
    required DateTime fecha,
    required num valorKg,
    required String naturaleza,
    String? metodo,
    String? observaciones,
  }) =>
      _db.from('pesajes').insert({
        'id': nuevoId(),
        'finca_id': fincaId,
        'animal_id': animalId,
        'fecha_pesaje': fecha.toUtc().toIso8601String(),
        'valor': valorKg,
        'naturaleza': naturaleza, // obligatorio: nunca se asume
        'metodo': _texto(metodo),
        'observaciones': _texto(observaciones),
      });

  static String? _texto(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
}

final animalesRepoProvider = Provider<AnimalesRepositorio>((ref) => AnimalesSupabase(ref.watch(supabaseProvider)));

final animalesProvider = FutureProvider<List<Animal>>((ref) async {
  final finca = ref.watch(fincaActualProvider);
  if (finca == null) return const [];
  return ref.watch(animalesRepoProvider).listar(finca.id);
});

final animalProvider = FutureProvider.family<Animal, String>((ref, id) => ref.watch(animalesRepoProvider).obtener(id));
final pesajesProvider = FutureProvider.family<List<Pesaje>, String>((ref, id) => ref.watch(animalesRepoProvider).pesajes(id));
