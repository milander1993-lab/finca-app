import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase.dart';
import '../../../core/widgets.dart';

/// Inicio de sesión con correo y contraseña (Supabase Auth).
class LoginPantalla extends ConsumerStatefulWidget {
  const LoginPantalla({super.key});
  @override
  ConsumerState<LoginPantalla> createState() => _LoginPantallaState();
}

class _LoginPantallaState extends ConsumerState<LoginPantalla> {
  final _correo = TextEditingController();
  final _clave = TextEditingController();
  bool _ocupado = false;

  Future<void> _entrar({required bool registrar}) async {
    setState(() => _ocupado = true);
    final auth = ref.read(supabaseProvider).auth;
    try {
      if (registrar) {
        final r = await auth.signUp(
          email: _correo.text.trim(),
          password: _clave.text,
          emailRedirectTo: 'https://milander1993-lab.github.io/finca-app/',
        );
        if (mounted && r.session == null) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Cuenta creada'),
              content: Text('Le enviamos un correo a ${_correo.text.trim()}.\n\n'
                  '1. Ábralo (revise también Spam o Promociones).\n'
                  '2. Toque "Confirm your mail".\n'
                  '3. Vuelva aquí y toque "Entrar" con el mismo correo y contraseña.\n\n'
                  'No toque "Crear cuenta" otra vez: la cuenta ya existe.'),
              actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
            ),
          );
        }
      } else {
        await auth.signInWithPassword(email: _correo.text.trim(), password: _clave.text);
      }
    } catch (e) {
      if (mounted) mostrarMensaje(context, mensajeError(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
              Text('Finca', style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextField(controller: _correo, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo')),
              const SizedBox(height: 12),
              TextField(controller: _clave, obscureText: true, decoration: const InputDecoration(labelText: 'Contraseña')),
              const SizedBox(height: 16),
              FilledButton(onPressed: _ocupado ? null : () => _entrar(registrar: false), child: const Text('Entrar')),
              TextButton(onPressed: _ocupado ? null : () => _entrar(registrar: true), child: const Text('Crear cuenta')),
            ]),
          ),
        ),
      );
}
