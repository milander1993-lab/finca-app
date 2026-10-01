import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/entidades/catalogo.dart';
import '../core/entidades/expediente_entidad.dart';
import '../core/entidades/form_entidad.dart';
import '../core/entidades/lista_entidad.dart';
import '../core/supabase.dart';
import '../features/agenda/agenda_pantalla.dart';
import '../features/animales/presentation/animal_detalle_pantalla.dart';
import '../features/animales/presentation/animal_form_pantalla.dart';
import '../features/animales/presentation/animales_pantalla.dart';
import '../features/auth/presentation/login_pantalla.dart';
import '../features/busqueda/busqueda_pantalla.dart';
import '../features/config/config_pantalla.dart';
import '../features/guias/guias.dart';
import '../features/ia/ia.dart';
import '../features/informes/informes_pantalla.dart';
import '../features/inicio/inicio_pantalla.dart';
import '../features/lotes/presentation/lotes_pantalla.dart';
import '../features/mapa/presentation/mapa_ruta.dart';
import '../features/monitoreo/monitoreo_pantalla.dart';
import '../features/pasturas/presentation/aforo_pantalla.dart';
import '../features/pasturas/presentation/potreros_pantalla.dart';
import '../features/qr/presentation/qr_ruta.dart';
import 'pilares.dart';

/// Refresca el router cuando cambia la sesión.
class _Refresco extends ChangeNotifier {
  _Refresco(Ref ref) {
    ref.listen(sesionProvider, (_, __) => notifyListeners());
  }
}

Widget _moduloDesconocido(String tabla) =>
    Scaffold(appBar: AppBar(), body: Center(child: Text('Módulo "$tabla" no encontrado')));

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
        GoRoute(path: 'p/:pilar', builder: (_, s) => PilarPantalla(id: s.pathParameters['pilar']!)),
        GoRoute(
          path: 'e/:tabla',
          builder: (_, s) {
            final t = s.pathParameters['tabla']!;
            if (!catalogo.containsKey(t)) return _moduloDesconocido(t);
            return ListaEntidadPantalla(tabla: t, filtros: Map<String, String>.from(s.uri.queryParameters));
          },
          routes: [
            GoRoute(
              path: 'nuevo',
              builder: (_, s) {
                final t = s.pathParameters['tabla']!;
                if (!catalogo.containsKey(t)) return _moduloDesconocido(t);
                return FormEntidadPantalla(tabla: t, iniciales: Map<String, String>.from(s.uri.queryParameters));
              },
            ),
            GoRoute(
              path: ':id',
              builder: (_, s) {
                final t = s.pathParameters['tabla']!;
                if (!catalogo.containsKey(t)) return _moduloDesconocido(t);
                return ExpedienteEntidadPantalla(tabla: t, id: s.pathParameters['id']!);
              },
              routes: [
                GoRoute(
                  path: 'editar',
                  builder: (_, s) {
                    final t = s.pathParameters['tabla']!;
                    if (!catalogo.containsKey(t)) return _moduloDesconocido(t);
                    return FormEntidadPantalla(tabla: t, id: s.pathParameters['id']!);
                  },
                ),
              ],
            ),
          ],
        ),
        GoRoute(path: 'agenda', builder: (_, __) => const AgendaPantalla()),
        GoRoute(path: 'buscar', builder: (_, __) => const BusquedaPantalla()),
        GoRoute(path: 'informes', builder: (_, __) => const InformesPantalla()),
        GoRoute(path: 'config', builder: (_, __) => const ConfigPantalla()),
        GoRoute(path: 'monitoreo', builder: (_, __) => const MonitoreoPantalla()),
        GoRoute(path: 'mapa', builder: (_, __) => const MapaRuta()),
        GoRoute(path: 'ia', builder: (_, __) => const IaHistorialPantalla()),
        GoRoute(path: 'guias', builder: (_, __) => const GuiasPantalla(), routes: [
          GoRoute(path: ':id', builder: (_, s) => GuiaDetallePantalla(id: s.pathParameters['id']!)),
        ]),
      ]),
    ],
  );
});
