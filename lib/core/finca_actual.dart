import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'supabase.dart';

class Finca {
  const Finca(this.id, this.nombre);
  final String id;
  final String nombre;
}

/// Fincas donde el usuario es miembro (RLS ya filtra).
final fincasProvider = FutureProvider<List<Finca>>((ref) async {
  ref.watch(sesionProvider);
  final filas = await ref.watch(supabaseProvider).from('fincas').select('id, nombre').eq('is_deleted', false).order('nombre');
  return [for (final f in filas) Finca(f['id'] as String, f['nombre'] as String)];
});

/// Finca seleccionada. Si hay una sola, se usa esa.
final fincaSeleccionadaIdProvider = StateProvider<String?>((ref) => null);

final fincaActualProvider = Provider<Finca?>((ref) {
  final lista = ref.watch(fincasProvider).valueOrNull ?? const [];
  final id = ref.watch(fincaSeleccionadaIdProvider);
  if (lista.isEmpty) return null;
  return lista.firstWhere((f) => f.id == id, orElse: () => lista.first);
});
