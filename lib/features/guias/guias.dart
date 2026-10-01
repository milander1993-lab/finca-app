import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/finca_actual.dart';
import '../../core/supabase.dart';
import '../../core/widgets.dart';

/// Los elementos de la regla de oro técnica (Prompt Maestro §2), en orden de lectura.
const elementosGuia = <MapEntry<String, String>>[
  MapEntry('que_es', 'Qué es'),
  MapEntry('para_que', 'Para qué se hace'),
  MapEntry('por_que', 'Por qué se hace'),
  MapEntry('donde', 'Dónde se realiza'),
  MapEntry('cuando', 'Cuándo se realiza'),
  MapEntry('quien_puede', 'Quién puede realizarlo'),
  MapEntry('como', 'Cómo se realiza'),
  MapEntry('metodo', 'Método'),
  MapEntry('materiales', 'Materiales'),
  MapEntry('equipos', 'Equipos'),
  MapEntry('unidades', 'Unidades'),
  MapEntry('preparacion', 'Preparación'),
  MapEntry('pasos', 'Pasos'),
  MapEntry('precauciones', 'Precauciones'),
  MapEntry('errores_comunes', 'Errores comunes'),
  MapEntry('prohibiciones', 'Prohibiciones'),
  MapEntry('condiciones_suspension', 'Condiciones de suspensión'),
  MapEntry('criterios_aceptacion', 'Criterios de aceptación'),
  MapEntry('registro', 'Cómo registrar'),
  MapEntry('evidencia', 'Evidencia requerida'),
  MapEntry('validacion', 'Validación'),
  MapEntry('seguimiento', 'Seguimiento'),
  MapEntry('fuente', 'Fuente'),
];

class GuiaConVersion {
  GuiaConVersion(this.guia, this.versiones);
  final Map<String, dynamic> guia;
  final List<Map<String, dynamic>> versiones;

  /// Versión vigente: la publicada; si no hay, la más reciente (borrador).
  Map<String, dynamic>? get vigente {
    for (final v in versiones) {
      if (v['estado'] == 'publicada') return v;
    }
    return versiones.isEmpty ? null : versiones.first;
  }

  String get estado => vigente == null ? 'sin versión' : '${vigente!['estado']}';
  int get faltantes {
    final v = vigente;
    if (v == null) return elementosGuia.length;
    return elementosGuia.where((e) => '${v[e.key] ?? ''}'.trim().isEmpty).length;
  }
}

final guiasProvider = FutureProvider.autoDispose<List<GuiaConVersion>>((ref) async {
  final finca = ref.watch(fincaActualProvider);
  if (finca == null) return const [];
  final db = ref.watch(supabaseProvider);
  final guias = await db.from('guias').select().eq('finca_id', finca.id).eq('is_deleted', false).order('titulo');
  final versiones = await db
      .from('guia_versiones')
      .select()
      .eq('finca_id', finca.id)
      .eq('is_deleted', false)
      .order('numero', ascending: false);
  return [
    for (final g in guias)
      GuiaConVersion(Map<String, dynamic>.from(g),
          [for (final v in versiones) if (v['guia_id'] == g['id']) Map<String, dynamic>.from(v)]),
  ];
});

final guiaPorCodigoProvider = FutureProvider.autoDispose.family<GuiaConVersion?, String>((ref, codigo) async {
  final lista = await ref.watch(guiasProvider.future);
  for (final g in lista) {
    if ('${g.guia['codigo']}'.toLowerCase() == codigo.toLowerCase()) return g;
  }
  return null;
});

final guiaPorIdProvider = FutureProvider.autoDispose.family<GuiaConVersion?, String>((ref, id) async {
  final lista = await ref.watch(guiasProvider.future);
  for (final g in lista) {
    if (g.guia['id'] == id) return g;
  }
  return null;
});

/// Contenido de una versión de guía (lo vacío se muestra como pendiente, no se rellena).
class ContenidoGuia extends StatelessWidget {
  const ContenidoGuia({super.key, required this.version});
  final Map<String, dynamic> version;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, children: [
        ChipEstado('Versión ${version['numero']}', icono: Icons.history),
        ChipEstado(etiquetaGuia('${version['estado']}'), icono: Icons.verified_outlined),
      ]),
      if (version['estado'] != 'publicada')
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            'Borrador: contiene solo lo que la arquitectura ya define. Lo vacío está pendiente de contenido técnico validado '
            '(no se inventa). Se publica cuando estén los 22 elementos, la fuente y quien revisa.',
            style: tema.textTheme.bodySmall,
          ),
        ),
      for (final e in elementosGuia)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.value, style: tema.textTheme.labelLarge),
            Text(
              '${version[e.key] ?? ''}'.trim().isEmpty ? 'Pendiente de contenido validado' : '${version[e.key]}',
              style: '${version[e.key] ?? ''}'.trim().isEmpty
                  ? tema.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)
                  : tema.textTheme.bodyMedium,
            ),
          ]),
        ),
    ]);
  }
}

String etiquetaGuia(String estado) => switch (estado) {
      'borrador' => 'Borrador',
      'en_revision' => 'En revisión',
      'publicada' => 'Publicada',
      'reemplazada' => 'Reemplazada',
      'anulada' => 'Anulada',
      _ => estado,
    };

/// Lista de guías y procedimientos (regla de oro técnica).
class GuiasPantalla extends ConsumerWidget {
  const GuiasPantalla({super.key});

  Future<void> _crearBase(BuildContext context, WidgetRef ref) async {
    final finca = ref.read(fincaActualProvider);
    if (finca == null) return;
    try {
      final n = await ref.read(supabaseProvider).rpc('crear_guias_base', params: {'p_finca': finca.id});
      ref.invalidate(guiasProvider);
      if (context.mounted) mostrarMensaje(context, 'Guías base creadas: $n (en borrador).');
    } catch (e) {
      if (context.mounted) mostrarMensaje(context, mensajeError(e));
    }
  }

  Future<void> _nueva(BuildContext context, WidgetRef ref) async {
    final finca = ref.read(fincaActualProvider);
    if (finca == null) return;
    final titulo = await pedirTexto(context, titulo: 'Nueva guía', etiqueta: 'Título (p. ej. Pesaje de terneros)');
    if (titulo == null || !context.mounted) return;
    final codigo = await pedirTexto(context,
        titulo: 'Código de la guía', etiqueta: 'Código corto sin espacios', ayuda: 'Se usa para enlazar la guía a la captura');
    if (codigo == null) return;
    try {
      final db = ref.read(supabaseProvider);
      final id = nuevoId();
      await db.from('guias').insert({'id': id, 'finca_id': finca.id, 'codigo': codigo.replaceAll(' ', '_'), 'titulo': titulo});
      await db.from('guia_versiones').insert({'id': nuevoId(), 'finca_id': finca.id, 'guia_id': id, 'numero': 1, 'estado': 'borrador'});
      ref.invalidate(guiasProvider);
      if (context.mounted) context.push('/guias/$id');
    } catch (e) {
      if (context.mounted) mostrarMensaje(context, mensajeError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guias = ref.watch(guiasProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Guías y procedimientos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _nueva(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nueva guía'),
      ),
      body: guias.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Vacio(mensajeError(e)),
        data: (lista) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(guiasProvider),
          child: ListView(padding: const EdgeInsets.all(12), children: [
            const Text(
              'Regla de oro: toda medición o procedimiento tiene una guía que explica qué es, para qué, por qué, dónde, '
              'cuándo, quién, cómo, método, materiales, equipos, unidades, preparación, pasos, precauciones, errores, '
              'prohibiciones, suspensión, aceptación, registro, evidencia, validación, seguimiento, fuente y versión.',
            ),
            const SizedBox(height: 8),
            if (lista.isEmpty)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.auto_stories),
                  title: const Text('Crear las guías base'),
                  subtitle: const Text(
                      'Suelo, aforo, lluvia, pesaje, pastoreo, sanidad, fotografía, georreferenciación y demanda de MS, '
                      'con el contenido que ya define la arquitectura (en borrador).'),
                  onTap: () => _crearBase(context, ref),
                ),
              ),
            for (final g in lista)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.menu_book),
                  title: Text('${g.guia['titulo']}'),
                  subtitle: Text('${etiquetaGuia(g.estado)} · ${g.faltantes} elemento(s) pendientes · código ${g.guia['codigo']}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/guias/${g.guia['id']}'),
                ),
              ),
            if (lista.isNotEmpty)
              TextButton.icon(
                onPressed: () => _crearBase(context, ref),
                icon: const Icon(Icons.library_add),
                label: const Text('Agregar las guías base que falten'),
              ),
            const SizedBox(height: 80),
          ]),
        ),
      ),
    );
  }
}

/// Detalle de una guía: versión vigente, historial de versiones, editar borrador,
/// crear nueva versión y publicar (la base exige los 22 elementos + fuente + revisor).
class GuiaDetallePantalla extends ConsumerWidget {
  const GuiaDetallePantalla({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(guiaPorIdProvider(id));
    return Scaffold(
      appBar: AppBar(title: Text(g.valueOrNull?.guia['titulo']?.toString() ?? 'Guía')),
      body: g.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Vacio(mensajeError(e)),
        data: (guia) {
          if (guia == null) return const Vacio('Guía no encontrada');
          final v = guia.vigente;
          final borrador = guia.versiones.where((x) => x['estado'] == 'borrador' || x['estado'] == 'en_revision').toList();
          return ListView(padding: const EdgeInsets.all(12), children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (borrador.isNotEmpty)
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => EditarVersionGuia(version: borrador.first))),
                  icon: const Icon(Icons.edit),
                  label: const Text('Editar borrador'),
                ),
              if (borrador.isEmpty && v != null)
                OutlinedButton.icon(
                  onPressed: () async {
                    final finca = ref.read(fincaActualProvider);
                    if (finca == null) return;
                    final copia = Map<String, dynamic>.from(v)
                      ..removeWhere((k, _) => const [
                            'id', 'created_at', 'updated_at', 'created_by', 'updated_by', 'version', 'publicada_en',
                            'revisado_por', 'estado', 'numero', 'is_deleted', 'sincronizada_en'
                          ].contains(k));
                    try {
                      final numero = (guia.versiones.map((x) => x['numero'] as int).fold<int>(0, (a, b) => a > b ? a : b)) + 1;
                      await ref.read(supabaseProvider).from('guia_versiones').insert(
                          {...copia, 'id': nuevoId(), 'numero': numero, 'estado': 'borrador'});
                      ref.invalidate(guiasProvider);
                    } catch (e) {
                      if (context.mounted) mostrarMensaje(context, mensajeError(e));
                    }
                  },
                  icon: const Icon(Icons.call_split),
                  label: const Text('Nueva versión (corregir)'),
                ),
              if (borrador.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () async {
                    final uid = ref.read(supabaseProvider).auth.currentUser?.id;
                    try {
                      final db = ref.read(supabaseProvider);
                      await db
                          .from('guia_versiones')
                          .update({'estado': 'publicada', 'revisado_por': uid}).eq('id', borrador.first['id']);
                      ref.invalidate(guiasProvider);
                      if (context.mounted) mostrarMensaje(context, 'Guía publicada.');
                    } catch (e) {
                      if (context.mounted) mostrarMensaje(context, mensajeError(e));
                    }
                  },
                  icon: const Icon(Icons.verified),
                  label: const Text('Publicar (yo la revisé)'),
                ),
            ]),
            const SizedBox(height: 12),
            if (v == null) const Text('Sin versiones') else ContenidoGuia(version: v),
            const Divider(height: 32),
            Text('Historial de versiones', style: Theme.of(context).textTheme.titleMedium),
            for (final x in guia.versiones)
              ListTile(
                dense: true,
                leading: const Icon(Icons.history),
                title: Text('Versión ${x['numero']} · ${etiquetaGuia('${x['estado']}')}'),
                subtitle: Text('Creada ${fechaCorta(x['created_at'])}${x['publicada_en'] != null ? ' · publicada ${fechaCorta(x['publicada_en'])}' : ''}'),
              ),
          ]);
        },
      ),
    );
  }
}

/// Edición de un borrador de guía (los 22 elementos + fuente).
class EditarVersionGuia extends ConsumerStatefulWidget {
  const EditarVersionGuia({super.key, required this.version});
  final Map<String, dynamic> version;
  @override
  ConsumerState<EditarVersionGuia> createState() => _EditarVersionGuiaState();
}

class _EditarVersionGuiaState extends ConsumerState<EditarVersionGuia> {
  late final Map<String, TextEditingController> _c = {
    for (final e in elementosGuia) e.key: TextEditingController(text: '${widget.version[e.key] ?? ''}'),
  };
  bool _guardando = false;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      await ref.read(supabaseProvider).from('guia_versiones').update({
        for (final e in _c.entries) e.key: e.value.text.trim().isEmpty ? null : e.value.text.trim(),
      }).eq('id', widget.version['id']);
      ref.invalidate(guiasProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) mostrarMensaje(context, mensajeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Borrador · versión ${widget.version['numero']}')),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          const Text('Escriba solo contenido con fuente. "No aplica" debe escribirse explícitamente; vacío = pendiente.'),
          const SizedBox(height: 8),
          for (final e in elementosGuia) ...[
            TextField(
              controller: _c[e.key],
              minLines: 1,
              maxLines: 8,
              decoration: InputDecoration(labelText: e.value),
            ),
            const SizedBox(height: 10),
          ],
          FilledButton.icon(
            onPressed: _guardando ? null : _guardar,
            icon: const Icon(Icons.save),
            label: const Text('Guardar borrador'),
          ),
          const SizedBox(height: 40),
        ]),
      );
}
