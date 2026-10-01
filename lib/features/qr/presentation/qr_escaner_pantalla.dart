import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/qr_repositorio.dart';
import '../domain/qr_estado.dart';
import '../domain/qr_operacion.dart';
import 'qr_providers.dart';

/// Escanea un QR y muestra su estado con las acciones posibles.
/// La selección de animal se delega a [elegirAnimal] (la pantalla de animales
/// real no fue entregada). Devuelve el id del animal o null si se cancela.
class QrEscanerPantalla extends ConsumerStatefulWidget {
  const QrEscanerPantalla({super.key, required this.fincaId, required this.elegirAnimal});
  final String fincaId;
  final Future<String?> Function(BuildContext) elegirAnimal;

  @override
  ConsumerState<QrEscanerPantalla> createState() => _QrEscanerPantallaState();
}

class _QrEscanerPantallaState extends ConsumerState<QrEscanerPantalla> {
  final _controlador = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  String? _codigo;
  QrVista? _vista;
  bool _ocupado = false;

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  Future<void> _alLeer(BarcodeCapture captura) async {
    if (_ocupado) return;
    final codigo = normalizarCodigo(captura.barcodes.firstOrNull?.rawValue);
    if (codigo == null) return;
    _ocupado = true;
    final vista = await ref.read(qrRepositorioProvider).consultar(widget.fincaId, codigo);
    if (!mounted) return;
    setState(() {
      _codigo = codigo;
      _vista = vista;
    });
    _ocupado = false;
  }

  Future<void> _ejecutar(QrTipoOperacion tipo) async {
    final codigo = _codigo;
    if (codigo == null) return;
    String? animalId;
    String? motivo;
    if (tipo == QrTipoOperacion.asignar) {
      animalId = await widget.elegirAnimal(context);
      if (animalId == null) return;
    }
    if (tipo == QrTipoOperacion.liberar) {
      animalId = _vista?.animalActualId;
      motivo = await _pedirMotivo();
      if (motivo == null) return;
    }
    if (tipo == QrTipoOperacion.confirmar) animalId = _vista?.animalActualId;
    try {
      await ref.read(qrRepositorioProvider).solicitar(
            fincaId: widget.fincaId,
            codigoLeido: codigo,
            tipo: tipo,
            animalId: animalId,
            motivo: motivo,
          );
      if (!mounted) return;
      // El resultado real lo decide el servidor al sincronizar; se informa sin afirmar éxito.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registrado en el dispositivo. Pendiente de confirmar con el servidor.')),
      );
      final vista = await ref.read(qrRepositorioProvider).consultar(widget.fincaId, codigo);
      if (mounted) setState(() => _vista = vista);
    } on QrOperacionInvalida catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensaje)));
    }
  }

  Future<String?> _pedirMotivo() {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Motivo de la liberación'),
        content: TextField(controller: c, autofocus: true, maxLines: 2),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Aceptar')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final acciones = _accionesPosibles();
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear QR')),
      body: Column(children: [
        Expanded(child: MobileScanner(controller: _controlador, onDetect: _alLeer)),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_codigo == null
                ? 'Apunte la cámara al código.'
                : 'Código: $_codigo — ${_vista == null ? "no registrado en este dispositivo" : _vista!.estado.name}'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final a in acciones)
                FilledButton.tonal(onPressed: () => _ejecutar(a.$1), child: Text(a.$2)),
            ]),
          ]),
        ),
      ]),
    );
  }

  List<(QrTipoOperacion, String)> _accionesPosibles() {
    if (_codigo == null) return const [];
    final v = _vista;
    if (v == null) return const [(QrTipoOperacion.registrar, 'Registrar código')];
    return switch (v.estado) {
      QrEstado.disponible => const [(QrTipoOperacion.asignar, 'Asignar a animal')],
      QrEstado.asignado => const [
          (QrTipoOperacion.confirmar, 'Confirmar chapa puesta'),
          (QrTipoOperacion.liberar, 'Liberar'),
        ],
      QrEstado.activo => const [(QrTipoOperacion.liberar, 'Liberar')],
      QrEstado.liberado => const [(QrTipoOperacion.habilitar, 'Habilitar de nuevo')],
    };
  }
}
