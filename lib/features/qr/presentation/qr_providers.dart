import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase.dart';
import '../data/qr_repositorio.dart';
import '../data/qr_supabase.dart';

/// Implementación por defecto: Supabase en línea. La capa offline puede
/// sobrescribir este provider sin tocar las pantallas (DT-010).
final qrFuenteDatosProvider = Provider<QrFuenteDatos>((ref) => QrSupabase(ref.watch(supabaseProvider)));

final qrGeneradorIdProvider = Provider<GeneradorId>((ref) => nuevoId);

final qrRepositorioProvider = Provider<QrRepositorio>(
  (ref) => QrRepositorio(ref.watch(qrFuenteDatosProvider), ref.watch(qrGeneradorIdProvider)),
);

/// Sigue el resultado sincronizado de una solicitud.
final qrResultadoProvider = StreamProvider.family<QrResultadoSync, String>(
  (ref, id) => ref.watch(qrRepositorioProvider).seguir(id),
);
