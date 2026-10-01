import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../finca_actual.dart';
import '../supabase.dart';

typedef Fila = Map<String, dynamic>;

/// Acceso genérico a cualquier tabla de la finca (RLS por membresía en el servidor).
/// La pantalla nunca llama a Supabase directamente (DT-010).
class RepoGenerico {
  RepoGenerico(this._db);
  final SupabaseClient _db;

  Future<List<Fila>> listar(String tabla, String fincaId,
      {Map<String, String> filtros = const {}, String orden = 'created_at', bool asc = false, int limite = 300}) async {
    var q = _db.from(tabla).select().eq('finca_id', fincaId).eq('is_deleted', false);
    filtros.forEach((k, v) {
      q = v == 'null' ? q.isFilter(k, null) : q.eq(k, v);
    });
    final r = await q.order(orden, ascending: asc).limit(limite);
    return List<Fila>.from(r);
  }

  Future<Fila?> obtener(String tabla, String id) async {
    final r = await _db.from(tabla).select().eq('id', id).maybeSingle();
    return r;
  }

  Future<String> crear(String tabla, String fincaId, Fila datos) async {
    final id = nuevoId();
    await _db.from(tabla).insert({...datos, 'id': id, 'finca_id': fincaId});
    return id;
  }

  Future<void> actualizar(String tabla, String id, Fila cambios) async {
    await _db.from(tabla).update(cambios).eq('id', id);
  }

  /// Anular ≠ borrar (D-010): queda en la historia con su motivo.
  Future<void> anular(String tabla, String id, String motivo, {bool conMotivo = true}) async {
    await _db.from(tabla).update({
      'is_deleted': true,
      if (conMotivo) 'motivo_anulacion': motivo,
    }).eq('id', id);
  }

  Future<List<Fila>> auditoria(String tabla, String id) async {
    final r = await _db
        .from('auditoria')
        .select('accion, estado_anterior, estado_nuevo, created_at, actor_id, motivo')
        .eq('tabla_afectada', tabla)
        .eq('registro_id', id)
        .order('created_at', ascending: false)
        .limit(100);
    return List<Fila>.from(r);
  }

  /// Opciones para un campo de referencia (id → etiqueta).
  Future<List<MapEntry<String, String>>> opcionesReferencia(
      String tabla, String etiqueta, String fincaId, Map<String, String>? filtro) async {
    var q = _db.from(tabla).select('id, $etiqueta').eq('finca_id', fincaId).eq('is_deleted', false);
    filtro?.forEach((k, v) => q = q.eq(k, v));
    final r = await q.order(etiqueta).limit(500);
    return [for (final f in r) MapEntry(f['id'] as String, '${f[etiqueta] ?? '(sin nombre)'}')];
  }

  /// Registros de otras tablas vinculados a un objeto (objeto_tipo/objeto_id u origen).
  Future<List<Fila>> vinculados(String tabla, String fincaId, String objetoTipo, String objetoId) async {
    final r = await _db
        .from(tabla)
        .select()
        .eq('finca_id', fincaId)
        .eq('is_deleted', false)
        .or('and(objeto_tipo.eq.$objetoTipo,objeto_id.eq.$objetoId)${tabla == 'actividades' ? ',origen_id.eq.$objetoId' : ''}')
        .order('created_at', ascending: false)
        .limit(100);
    return List<Fila>.from(r);
  }

  Future<dynamic> rpc(String funcion, Map<String, dynamic> params) => _db.rpc(funcion, params: params);
}

final repoProvider = Provider<RepoGenerico>((ref) => RepoGenerico(ref.watch(supabaseProvider)));

/// Clave de consulta de lista: "tabla" o "tabla?campo=valor&campo2=valor2".
class ConsultaLista {
  ConsultaLista(this.tabla, [this.filtros = const {}]);
  final String tabla;
  final Map<String, String> filtros;

  @override
  bool operator ==(Object other) =>
      other is ConsultaLista && other.tabla == tabla && _mapaIgual(other.filtros, filtros);

  @override
  int get hashCode => Object.hash(tabla, Object.hashAllUnordered(filtros.entries.map((e) => '${e.key}=${e.value}')));
}

bool _mapaIgual(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final k in a.keys) {
    if (a[k] != b[k]) return false;
  }
  return true;
}

final listaProvider = FutureProvider.autoDispose.family<List<Fila>, ConsultaLista>((ref, c) async {
  final finca = ref.watch(fincaActualProvider);
  if (finca == null) return const [];
  return ref.watch(repoProvider).listar(c.tabla, finca.id, filtros: c.filtros);
});

class ClaveRegistro {
  const ClaveRegistro(this.tabla, this.id);
  final String tabla;
  final String id;
  @override
  bool operator ==(Object other) => other is ClaveRegistro && other.tabla == tabla && other.id == id;
  @override
  int get hashCode => Object.hash(tabla, id);
}

final registroProvider = FutureProvider.autoDispose.family<Fila?, ClaveRegistro>((ref, c) {
  return ref.watch(repoProvider).obtener(c.tabla, c.id);
});

final auditoriaProvider = FutureProvider.autoDispose.family<List<Fila>, ClaveRegistro>((ref, c) {
  return ref.watch(repoProvider).auditoria(c.tabla, c.id);
});

/// Vinculados: tabla destino + objeto (tabla, id).
class ClaveVinculo {
  const ClaveVinculo(this.tablaDestino, this.objetoTipo, this.objetoId);
  final String tablaDestino;
  final String objetoTipo;
  final String objetoId;
  @override
  bool operator ==(Object other) =>
      other is ClaveVinculo && other.tablaDestino == tablaDestino && other.objetoTipo == objetoTipo && other.objetoId == objetoId;
  @override
  int get hashCode => Object.hash(tablaDestino, objetoTipo, objetoId);
}

final vinculadosProvider = FutureProvider.autoDispose.family<List<Fila>, ClaveVinculo>((ref, c) async {
  final finca = ref.watch(fincaActualProvider);
  if (finca == null) return const [];
  return ref.watch(repoProvider).vinculados(c.tablaDestino, finca.id, c.objetoTipo, c.objetoId);
});

/// Invalida todo lo que depende de una tabla (tareas conectadas: un cambio puede
/// crear actividades, alertas o cambiar decisiones en el servidor).
void refrescarTodo(WidgetRef ref) {
  ref.invalidate(listaProvider);
  ref.invalidate(registroProvider);
  ref.invalidate(vinculadosProvider);
  ref.invalidate(auditoriaProvider);
  ref.invalidate(tableroProvider);
}

/// Tablero (dashboard) de la finca: resumen, alertas, agenda, flujo e informes.
class PeriodoTablero {
  const PeriodoTablero(this.desde, this.hasta);
  final DateTime? desde;
  final DateTime? hasta;
  @override
  bool operator ==(Object other) => other is PeriodoTablero && other.desde == desde && other.hasta == hasta;
  @override
  int get hashCode => Object.hash(desde, hasta);
}

String fechaIso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

final tableroProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, PeriodoTablero>((ref, p) async {
  final finca = ref.watch(fincaActualProvider);
  if (finca == null) return const {};
  final r = await ref.watch(repoProvider).rpc('tablero_finca', {
    'p_finca': finca.id,
    'p_desde': p.desde == null ? null : fechaIso(p.desde!),
    'p_hasta': p.hasta == null ? null : fechaIso(p.hasta!),
  });
  return Map<String, dynamic>.from(r as Map);
});
