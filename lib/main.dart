import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/config.dart';

/// Arranque. La URL y la clave pública (anon) de Supabase se pasan al compilar:
///   flutter run -d chrome --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
/// Nunca se escribe una clave de servicio en el cliente (3.10).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Config.estaConfigurada) {
    runApp(const _SinConfiguracion());
    return;
  }
  await Supabase.initialize(url: Config.supabaseUrl, anonKey: Config.supabaseAnonKey);
  runApp(const ProviderScope(child: FincaApp()));
}

class _SinConfiguracion extends StatelessWidget {
  const _SinConfiguracion();
  @override
  Widget build(BuildContext context) => const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Falta configurar la conexión (SUPABASE_URL y SUPABASE_ANON_KEY).',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
}
