import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/supabase.dart';
import '../features/animales/presentation/animal_detalle_pantalla.dart';
import '../features/animales/presentation/animal_form_pantalla.dart';
import '../features/animales/presentation/animales_pantalla.dart';
import '../features/auth/presentation/login_pantalla.dart';
import '../features/inicio/presentation/inicio_pantalla.dart';
import '../features/lotes/presentation/lotes_pantalla.dart';
import '../features/pasturas/presentation/aforo_pantalla.dart';
import '../features/pasturas/presentation/potreros_pantalla.dart';
import '../features/qr/presentation/qr_ruta.dart';

/// Refresca el router cuando cambia la sesión.
class _Refresco extends ChangeNotifier {
  _Refresco(Ref ref) {
    ref.listen(sesionProvider, (_, __) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final cliente = ref.watch(supabaseProvider);
  return GoRouter(
    refreshListenable: _Refresco(ref),
    redirect: (context, estado) {
      final logueado = cliente.auth.currentSession != null;
      final enLogin = estado.matchedLocation == '/login';
      if (!logueado) return enLogin ? null : '/login';
      if (enLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginPantalla()),
      GoRoute(path: '/', builder: (_, __) => const InicioPantalla(), routes: [
        GoRoute(path: 'animales', builder: (_, __) => const AnimalesPantalla(), routes: [
          GoRoute(path: 'nuevo', builder: (_, __) => const AnimalFormPantalla()),
          GoRoute(path: ':id', builder: (_, s) => AnimalDetallePantalla(animalId: s.pathParameters['id']!)),
        ]),
        GoRoute(path: 'lotes', builder: (_, __) => const LotesPantalla()),
        GoRoute(path: 'potreros', builder: (_, __) => const PotrerosPantalla()),
        GoRoute(path: 'aforo/:aforoId', builder: (_, s) => AforoPantalla(aforoId: s.pathParameters['aforoId']!)),
        GoRoute(path: 'qr', builder: (_, __) => const QrRuta()),
      ]),
    ],
  );
});
