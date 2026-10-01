import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

/// Sesión actual (null = sin iniciar sesión).
final sesionProvider = StreamProvider<Session?>((ref) {
  final auth = ref.watch(supabaseProvider).auth;
  return auth.onAuthStateChange.map((e) => e.session);
});

const _uuid = Uuid();

/// Id generado en el cliente (offline-first: reintentar nunca duplica).
String nuevoId() => _uuid.v4();

/// Traduce errores de la base (reglas en triggers) a mensajes para el usuario.
/// Nunca se oculta el error (§69.17): si no se reconoce, se muestra el original.
String mensajeError(Object e) {
  if (e is PostgrestException) {
    switch (e.code) {
      case '23514': // check_violation
      case '23001': // restrict_violation
      case '23000': // integrity_constraint_violation
        return e.message;
      case '23505':
        return 'Ya existe un registro igual (${e.message}).';
      case '23502':
        return 'Falta un dato obligatorio (${e.message}).';
      case '42501':
        return 'No tiene permiso para esta finca.';
    }
    return e.message;
  }
  return e.toString();
}
