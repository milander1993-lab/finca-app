import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/finca_actual.dart';
import '../../../core/supabase.dart';
import '../domain/pasturas.dart';

abstract class PasturasRepositorio {
  Future<List<Unidad>> unidades(String fincaId);
  Future<void> crearPotrero(String fincaId, String nombre);
  Future<void> crearDivision(String fincaId, String potreroId, String nombre);
  Future<void> registrarSuperficie(String unidadId, num hectareas, String naturaleza);
  Future<List<OcupacionVista>> ocupaciones(String fincaId);
  Future<void> iniciarOcupacion({required String fincaId, required String unidadId, required String loteId, required DateTime entrada});
  Future<void> cerrarOcupacion(String ocupacionId, DateTime salida);
  Future<String> crearAforo({required String fincaId, required String unidadId, required DateTime fecha, required String naturaleza, String? metodo});
  Future<List<AforoResumen>> aforos(String fincaId);
  Future<AforoResumen> aforo(String aforoId);
  Future<List<MuestraAforo>> muestras(String aforoId);
  Future<void> agregarMuestra({required String fincaId, required String aforoId, required int punto, num? areaM2, num? mfG, num? msG});
  Future<void> registrarMateriaSeca(String muestraId, num msG);
}

class PasturasSupabase implements PasturasRepositorio {
  PasturasSupabase(this._db);
  final SupabaseClient _db;

  @override
  Future<List<Unidad>> unidades(String fincaId) async {
    final f = await _db.from('unidades_espaciales').select('id, tipo, nombre, parent_id, superficie_ha, superficie_naturaleza')
        .eq('finca_id', fincaId).eq('is_deleted', false).order('nombre');
    return [for (final m in f) Unidad.desdeMapa(m)];
  }

  @override
  Future<void> crearPotrero(String fincaId, String nombre) => _db.from('unidades_espaciales')
      .insert({'id': nuevoId(), 'finca_id': fincaId, 'tipo': 'potrero', 'nombre': nombre.trim(), 'es_temporal': false});

  @override
  Future<void> crearDivision(String fincaId, String potreroId, String nombre) => _db.from('unidades_espaciales').insert(
      {'id': nuevoId(), 'finca_id': fincaId, 'tipo': 'division', 'nombre': nombre.trim(), 'es_temporal': true, 'parent_id': potreroId});

  @override
  Future<void> registrarSuperficie(String unidadId, num hectareas, String naturaleza) =>
      _db.from('unidades_espaciales').update({'superficie_ha': hectareas, 'superficie_naturaleza': naturaleza}).eq('id', unidadId);

  @override
  Future<List<OcupacionVista>> ocupaciones(String fincaId) async {
    final f = await _db.from('v_alertas_ocupacion').select().eq('finca_id', fincaId).order('entrada_en', ascending: false).limit(200);
    return [for (final m in f) OcupacionVista.desdeMapa(m)];
  }

  @override
  Future<void> iniciarOcupacion({required String fincaId, required String unidadId, required String loteId, required DateTime entrada}) =>
      _db.from('ocupaciones_pastoreo').insert(
          {'id': nuevoId(), 'finca_id': fincaId, 'unidad_id': unidadId, 'lote_id': loteId, 'entrada_en': entrada.toUtc().toIso8601String()});

  @override
  Future<void> cerrarOcupacion(String ocupacionId, DateTime salida) =>
      _db.from('ocupaciones_pastoreo').update({'salida_en': salida.toUtc().toIso8601String()}).eq('id', ocupacionId);

  @override
  Future<String> crearAforo({required String fincaId, required String unidadId, required DateTime fecha, required String naturaleza, String? metodo}) async {
    final id = nuevoId();
    await _db.from('aforos').insert({
      'id': id,
      'finca_id': fincaId,
      'unidad_id': unidadId,
      'fecha_aforo': fecha.toUtc().toIso8601String(),
      'naturaleza': naturaleza,
      'metodo': (metodo == null || metodo.trim().isEmpty) ? null : metodo.trim(),
    });
    return id;
  }

  @override
  Future<List<AforoResumen>> aforos(String fincaId) async {
    final f = await _db.from('v_aforos_resumen').select().eq('finca_id', fincaId).order('fecha_aforo', ascending: false).limit(200);
    return [for (final m in f) AforoResumen.desdeMapa(m)];
  }

  @override
  Future<AforoResumen> aforo(String aforoId) async =>
      AforoResumen.desdeMapa(await _db.from('v_aforos_resumen').select().eq('aforo_id', aforoId).single());

  @override
  Future<List<MuestraAforo>> muestras(String aforoId) async {
    final f = await _db.from('aforo_muestras').select().eq('aforo_id', aforoId).eq('is_deleted', false).order('punto');
    return [for (final m in f) MuestraAforo.desdeMapa(m)];
  }

  @override
  Future<void> agregarMuestra({required String fincaId, required String aforoId, required int punto, num? areaM2, num? mfG, num? msG}) =>
      _db.from('aforo_muestras').insert({
        'id': nuevoId(),
        'finca_id': fincaId,
        'aforo_id': aforoId,
        'punto': punto,
        'area_muestra_m2': areaM2,
        'materia_fresca_g': mfG,
        'materia_seca_g': msG,
      });

  @override
  Future<void> registrarMateriaSeca(String muestraId, num msG) =>
      _db.from('aforo_muestras').update({'materia_seca_g': msG}).eq('id', muestraId);
}

final pasturasRepoProvider = Provider<PasturasRepositorio>((ref) => PasturasSupabase(ref.watch(supabaseProvider)));

final unidadesProvider = FutureProvider<List<Unidad>>((ref) async {
  final finca = ref.watch(fincaActualProvider);
  return finca == null ? const [] : ref.watch(pasturasRepoProvider).unidades(finca.id);
});

final ocupacionesProvider = FutureProvider<List<OcupacionVista>>((ref) async {
  final finca = ref.watch(fincaActualProvider);
  return finca == null ? const [] : ref.watch(pasturasRepoProvider).ocupaciones(finca.id);
});

final aforosProvider = FutureProvider<List<AforoResumen>>((ref) async {
  final finca = ref.watch(fincaActualProvider);
  return finca == null ? const [] : ref.watch(pasturasRepoProvider).aforos(finca.id);
});

final aforoProvider = FutureProvider.family<AforoResumen, String>((ref, id) => ref.watch(pasturasRepoProvider).aforo(id));
final muestrasProvider = FutureProvider.family<List<MuestraAforo>, String>((ref, id) => ref.watch(pasturasRepoProvider).muestras(id));
