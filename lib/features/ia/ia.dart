import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/entidades/catalogo.dart';
import '../../core/entidades/repo_generico.dart';
import '../../core/finca_actual.dart';
import '../../core/supabase.dart';
import '../../core/transversal/paneles.dart';
import '../../core/widgets.dart';

/// Funciones de la IA contextual (Prompt Maestro §60). La IA explica, guía, señala
/// faltantes, analiza y propone; nunca inventa datos, no calcula (D-016), no decide
/// y todo queda registrado en ia_interacciones con lo que consultó.
const funcionesIA = <String, String>{
  'explicar': 'Explicar este registro y su contexto',
  'faltantes': '¿Qué información falta?',
  'analizar': 'Analizar: señales, posibles inconsistencias y qué revisar',
  'proponer': 'Proponer recomendaciones con alternativas',
  'analizar_finca': 'Analizar el estado general de la finca',
};

class AsistenteIA extends ConsumerStatefulWidget {
  const AsistenteIA({super.key, this.funcion, this.tabla, this.id, this.titulo});
  final String? funcion;
  final String? tabla;
  final String? id;
  final String? titulo;

  static Future<void> abrir(BuildContext context, {String? funcion, String? tabla, String? id, String? titulo}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        builder: (context, scroll) => PrimaryScrollController(
          controller: scroll,
          child: AsistenteIA(funcion: funcion, tabla: tabla, id: id, titulo: titulo),
        ),
      ),
    );
  }

  @override
  ConsumerState<AsistenteIA> createState() => _AsistenteIAState();
}

class _AsistenteIAState extends ConsumerState<AsistenteIA> {
  final _pregunta = TextEditingController();
  bool _trabajando = false;
  Map<String, dynamic>? _respuesta;
  List<String>? _faltantes;

  @override
  void initState() {
    super.initState();
    _revisarFaltantes();
    if (widget.funcion == 'explicar_guia') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _consultar('explicar_guia'));
    }
  }

  @override
  void dispose() {
    _pregunta.dispose();
    super.dispose();
  }

  /// Revisión determinística (reglas, sin IA): campos vacíos del registro.
  Future<void> _revisarFaltantes() async {
    final t = widget.tabla;
    final id = widget.id;
    if (t == null || id == null || !catalogo.containsKey(t)) return;
    try {
      final fila = await ref.read(repoProvider).obtener(t, id);
      if (fila != null && mounted) setState(() => _faltantes = camposFaltantes(catalogo[t]!, fila));
    } catch (_) {}
  }

  Future<void> _consultar(String funcion) async {
    final finca = ref.read(fincaActualProvider);
    if (finca == null) return;
    setState(() {
      _trabajando = true;
      _respuesta = null;
    });
    try {
      final r = await ref.read(supabaseProvider).functions.invoke('ia-asistente', body: {
        'finca_id': finca.id,
        'funcion': funcion,
        'tabla': widget.tabla,
        'id': widget.id,
        'pregunta': _pregunta.text.trim().isEmpty ? null : _pregunta.text.trim(),
      });
      final datos = r.data;
      setState(() => _respuesta = datos is Map ? Map<String, dynamic>.from(datos) : {'salida': '$datos'});
    } catch (e) {
      setState(() => _respuesta = {
            'error': 'No se pudo consultar la IA: ${mensajeError(e)}. El resto de la app funciona sin IA.',
          });
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _accionHumana(String estado) async {
    final id = _respuesta?['interaccion_id'];
    if (id == null) return;
    final nota = await pedirTexto(context,
        titulo: estado == 'aceptada' ? 'Aceptar la respuesta' : 'Descartar la respuesta',
        etiqueta: 'Qué hará con esto (queda registrado)');
    if (nota == null) return;
    try {
      await ref.read(supabaseProvider).from('ia_interacciones').update({'estado': estado, 'accion_humana': nota}).eq('id', id);
      if (mounted) mostrarMensaje(context, 'Registrado.');
    } catch (e) {
      if (mounted) mostrarMensaje(context, mensajeError(e));
    }
  }

  Future<void> _crearRecomendacion() async {
    final finca = ref.read(fincaActualProvider);
    final r = _respuesta;
    if (finca == null || r == null) return;
    final titulo = await pedirTexto(context,
        titulo: 'Recomendación para revisar', etiqueta: 'Título', inicial: widget.titulo == null ? '' : 'Sobre ${widget.titulo}');
    if (titulo == null) return;
    try {
      final id = await ref.read(repoProvider).crear('recomendaciones', finca.id, {
        'titulo': titulo,
        'descripcion': r['salida'],
        'origen': 'ia',
        'ia_interaccion_id': r['interaccion_id'],
        'datos_usados': r['datos_consultados'],
        'metodo': 'Asistente de IA (${r['modelo'] ?? 'modelo no informado'})',
        'incertidumbre': r['incertidumbre'] ?? 'La IA puede equivocarse; requiere revisión humana.',
      });
      refrescarTodo(ref);
      if (mounted) {
        Navigator.pop(context);
        context.push('/e/recomendaciones/$id');
      }
    } catch (e) {
      if (mounted) mostrarMensaje(context, mensajeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final r = _respuesta;
    return ListView(
      primary: true,
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          const Icon(Icons.auto_awesome),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.titulo == null ? 'Asistente' : 'Asistente · ${widget.titulo}', style: tema.textTheme.titleLarge)),
        ]),
        const SizedBox(height: 4),
        Text(
          'La IA explica, señala faltantes, analiza y propone. No inventa datos, no calcula y no decide: '
          'todo lo que responde queda registrado y usted decide.',
          style: tema.textTheme.bodySmall,
        ),
        if (_faltantes != null) ...[
          const SizedBox(height: 12),
          Seccion(
            titulo: 'Revisión automática (reglas, sin IA): información faltante',
            icono: Icons.rule,
            hijos: [
              if (_faltantes!.isEmpty) const Text('No faltan campos en este registro.'),
              for (final f in _faltantes!) Text('• $f'),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in funcionesIA.entries)
            if (e.key != 'analizar_finca' || widget.tabla == null)
              ActionChip(
                avatar: const Icon(Icons.bolt, size: 16),
                label: Text(e.value),
                onPressed: _trabajando ? null : () => _consultar(e.key),
              ),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _pregunta,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'Pregunte en sus palabras',
            suffixIcon: IconButton(
              icon: const Icon(Icons.send),
              onPressed: _trabajando ? null : () => _consultar('preguntar'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_trabajando) const LinearProgressIndicator(),
        if (r != null && r['error'] != null) Text('${r['error']}', style: TextStyle(color: tema.colorScheme.error)),
        if (r != null && r['configurada'] == false)
          Seccion(
            titulo: 'IA pendiente de activar',
            icono: Icons.info_outline,
            hijos: [Text('${r['mensaje'] ?? 'Falta elegir el proveedor de IA y su clave (decisión 3.9).'}')],
          ),
        if (r != null && r['salida'] != null) ...[
          Seccion(
            titulo: 'Respuesta de la IA',
            icono: Icons.chat_bubble_outline,
            hijos: [
              SelectableText('${r['salida']}'),
              const SizedBox(height: 8),
              if (r['datos_consultados'] != null)
                Text('Datos consultados: ${r['datos_consultados']}', style: tema.textTheme.bodySmall),
              Text('Incertidumbre: ${r['incertidumbre'] ?? 'la IA puede equivocarse; verifique antes de actuar.'}',
                  style: tema.textTheme.bodySmall),
              if (r['modelo'] != null) Text('Modelo: ${r['modelo']}', style: tema.textTheme.bodySmall),
            ],
          ),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
                onPressed: () => _accionHumana('aceptada'), icon: const Icon(Icons.check), label: const Text('Aceptar')),
            OutlinedButton.icon(
                onPressed: () => _accionHumana('descartada'), icon: const Icon(Icons.close), label: const Text('Descartar')),
            FilledButton.icon(
              onPressed: _crearRecomendacion,
              icon: const Icon(Icons.lightbulb),
              label: const Text('Convertir en recomendación (para revisión)'),
            ),
          ]),
        ],
        const SizedBox(height: 40),
      ],
    );
  }
}

/// Historial de todo lo que la IA respondió (trazabilidad §60).
class IaHistorialPantalla extends ConsumerWidget {
  const IaHistorialPantalla({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final finca = ref.watch(fincaActualProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Asistente de IA')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => AsistenteIA.abrir(context, titulo: finca?.nombre),
        icon: const Icon(Icons.auto_awesome),
        label: const Text('Preguntar'),
      ),
      body: finca == null
          ? const Vacio('Sin finca')
          : FutureBuilder(
              future: ref
                  .read(supabaseProvider)
                  .from('ia_interacciones')
                  .select()
                  .eq('finca_id', finca.id)
                  .order('created_at', ascending: false)
                  .limit(100),
              builder: (context, s) {
                if (!s.hasData) {
                  return s.hasError ? Vacio(mensajeError(s.error!)) : const Center(child: CircularProgressIndicator());
                }
                final lista = s.data!;
                if (lista.isEmpty) return const Vacio('Todavía no hay consultas a la IA.', icono: Icons.auto_awesome);
                return ListView(padding: const EdgeInsets.all(12), children: [
                  for (final f in lista)
                    Card(
                      child: ExpansionTile(
                        leading: const Icon(Icons.auto_awesome),
                        title: Text('${funcionesIA[f['funcion']] ?? f['funcion']}'),
                        subtitle: Text('${fechaCorta(f['created_at'])} · ${f['estado']}'),
                        childrenPadding: const EdgeInsets.all(12),
                        children: [
                          Align(alignment: Alignment.centerLeft, child: Text('Entrada: ${f['entrada']}')),
                          const SizedBox(height: 6),
                          Align(
                              alignment: Alignment.centerLeft,
                              child: SelectableText('${f['salida'] ?? f['incertidumbre'] ?? 'sin salida'}')),
                          if (f['accion_humana'] != null)
                            Align(alignment: Alignment.centerLeft, child: Text('Acción humana: ${f['accion_humana']}')),
                        ],
                      ),
                    ),
                ]);
              },
            ),
    );
  }
}
