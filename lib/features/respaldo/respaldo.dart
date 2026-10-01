import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/finca_actual.dart';
import '../../core/supabase.dart';
import '../../core/widgets.dart';

/// Descarga un respaldo completo de la finca (RPC `exportar_finca`, migración 00015)
/// como archivo JSON para guardarlo en Google Drive. Incluye lo anulado: la historia no se pierde.
Future<void> descargarRespaldo(BuildContext context, WidgetRef ref) async {
  final finca = ref.read(fincaActualProvider);
  if (finca == null) return;
  try {
    final datos = await ref.read(supabaseProvider).rpc('exportar_finca', params: {'p_finca': finca.id});
    final bytes = Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent(' ').convert(datos)));
    final fecha = DateTime.now().toIso8601String().substring(0, 10);
    await FileSaver.instance.saveFile(name: 'respaldo_finca_$fecha', bytes: bytes, ext: 'json', mimeType: MimeType.json);
    if (context.mounted) mostrarMensaje(context, 'Respaldo descargado. Súbalo a su carpeta de Google Drive.');
  } catch (e) {
    if (context.mounted) mostrarMensaje(context, mensajeError(e));
  }
}
