import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/finca_actual.dart';
import '../../../core/widgets.dart';
import '../../animales/data/animales_repositorio.dart';
import 'qr_escaner_pantalla.dart';

/// Conecta el escáner QR con la finca actual y el selector de animales.
class QrRuta extends ConsumerWidget {
  const QrRuta({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final finca = ref.watch(fincaActualProvider);
    if (finca == null) return const Scaffold(body: Vacio('Sin finca seleccionada.'));
    return QrEscanerPantalla(
      fincaId: finca.id,
      elegirAnimal: (ctx) async {
        final animales = await ref.read(animalesProvider.future);
        if (!ctx.mounted) return null;
        return showDialog<String>(
          context: ctx,
          builder: (d) => SimpleDialog(title: const Text('¿Qué animal?'), children: [
            if (animales.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Sin animales registrados.')),
            for (final a in animales) SimpleDialogOption(onPressed: () => Navigator.pop(d, a.id), child: Text(a.numeroInterno)),
          ]),
        );
      },
    );
  }
}
