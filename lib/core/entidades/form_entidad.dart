import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../finca_actual.dart';
import '../supabase.dart';
import '../widgets.dart';
import '../transversal/paneles.dart';
import 'catalogo.dart';
import 'definicion.dart';
import 'repo_generico.dart';

/// Opciones de un campo de referencia (se cargan de la base, filtradas por finca).
class ClaveReferencia {
  const ClaveReferencia(this.tabla, this.etiqueta, this.filtro);
  final String tabla;
  final String etiqueta;
  final String filtro;
  @override
  bool operator ==(Object other) =>
      other is ClaveReferencia && other.tabla == tabla && other.etiqueta == etiqueta && other.filtro == filtro;
  @override
  int get hashCode => Object.hash(tabla, etiqueta, filtro);
}

final referenciasProvider =
    FutureProvider.autoDispose.family<List<MapEntry<String, String>>, ClaveReferencia>((ref, c) async {
  final finca = ref.watch(fincaActualProvider);
  if (finca == null) return const [];
  Map<String, String>? filtro;
  if (c.filtro.isNotEmpty) {
    filtro = {};
    for (final par in c.filtro.split('&')) {
      final i = par.indexOf('=');
      if (i > 0) filtro[par.substring(0, i)] = par.substring(i + 1);
    }
  }
  return ref.watch(repoProvider).opcionesReferencia(c.tabla, c.etiqueta, finca.id, filtro);
});

String _filtroTexto(Map<String, String>? f) => f == null ? '' : f.entries.map((e) => '${e.key}=${e.value}').join('&');

/// Formulario genérico: crea o edita un registro de cualquier entidad del catálogo.
/// Campos dinámicos, sin formularios gigantes: solo los campos de la entidad,
/// con su ayuda, unidad y la guía de la regla de oro arriba.
class FormEntidadPantalla extends ConsumerStatefulWidget {
  const FormEntidadPantalla({super.key, required this.tabla, this.id, this.iniciales = const {}});
  final String tabla;
  final String? id;
  final Map<String, String> iniciales;

  @override
  ConsumerState<FormEntidadPantalla> createState() => _FormEntidadPantallaState();
}

class _FormEntidadPantallaState extends ConsumerState<FormEntidadPantalla> {
  final _clave = GlobalKey<FormState>();
  final Map<String, dynamic> _valores = {};
  final Map<String, TextEditingController> _textos = {};
  bool _cargado = false;
  bool _guardando = false;

  EntidadDef get def => catalogo[widget.tabla]!;

  @override
  void initState() {
    super.initState();
    if (widget.id == null) {
      _valores.addAll(widget.iniciales);
      for (final c in def.campos) {
        if ((c.tipo == TipoCampo.fecha || c.tipo == TipoCampo.fechaHora) && c.obligatorio && _valores[c.clave] == null) {
          _valores[c.clave] = DateTime.now().toUtc().toIso8601String();
        }
        if (c.tipo == TipoCampo.booleano && _valores[c.clave] == null) _valores[c.clave] = false;
        if (c.tipo == TipoCampo.booleano && _valores[c.clave] is String) _valores[c.clave] = _valores[c.clave] == 'true';
      }
      _cargado = true;
    } else {
      _cargar();
    }
  }

  Future<void> _cargar() async {
    try {
      final fila = await ref.read(repoProvider).obtener(widget.tabla, widget.id!);
      if (fila != null) _valores.addAll(fila);
    } catch (e) {
      if (mounted) mostrarMensaje(context, mensajeError(e));
    }
    if (mounted) setState(() => _cargado = true);
  }

  @override
  void dispose() {
    for (final c in _textos.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controlador(String clave) =>
      _textos.putIfAbsent(clave, () => TextEditingController(text: _valores[clave]?.toString() ?? ''));

  Future<void> _guardar() async {
    if (!_clave.currentState!.validate()) return;
    final finca = ref.read(fincaActualProvider);
    if (finca == null) return;
    final datos = <String, dynamic>{};
    for (final c in def.campos.where((c) => c.enFormulario && !c.soloLectura)) {
      final v = _valor(c);
      if (widget.id != null || v != null) datos[c.clave] = v;
    }
    // Campos de solo lectura que vienen como iniciales (p. ej. objeto vinculado)
    if (widget.id == null) {
      for (final c in def.campos.where((c) => c.soloLectura || !c.enFormulario)) {
        final v = widget.iniciales[c.clave];
        if (v != null && v.isNotEmpty) datos[c.clave] = v;
      }
    }
    // Observaciones y evidencias sin objeto quedan vinculadas a la finca.
    if (widget.id == null && (widget.tabla == 'observaciones' || widget.tabla == 'evidencias') && datos['objeto_id'] == null) {
      datos['objeto_tipo'] = 'fincas';
      datos['objeto_id'] = finca.id;
    }
    setState(() => _guardando = true);
    try {
      final repo = ref.read(repoProvider);
      String id;
      if (widget.id == null) {
        id = await repo.crear(widget.tabla, finca.id, datos);
      } else {
        id = widget.id!;
        await repo.actualizar(widget.tabla, id, datos);
      }
      refrescarTodo(ref);
      if (!mounted) return;
      mostrarMensaje(context, 'Guardado. Las tareas y alertas conectadas se actualizan solas.');
      context.pushReplacement('/e/${widget.tabla}/$id');
    } catch (e) {
      if (mounted) mostrarMensaje(context, mensajeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  dynamic _valor(CampoDef c) {
    switch (c.tipo) {
      case TipoCampo.texto:
      case TipoCampo.textoLargo:
        final t = _controlador(c.clave).text.trim();
        return t.isEmpty ? null : t;
      case TipoCampo.entero:
        final t = _controlador(c.clave).text.trim();
        return t.isEmpty ? null : int.tryParse(t);
      case TipoCampo.decimal:
        final t = _controlador(c.clave).text.trim().replaceAll(',', '.');
        return t.isEmpty ? null : double.tryParse(t);
      default:
        final v = _valores[c.clave];
        if (v is String && v.isEmpty) return null;
        return v;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.id == null ? 'Nuevo: ${def.singular}' : 'Editar: ${def.singular}')),
      body: !_cargado
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _clave,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                if (def.descripcion.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(def.descripcion, style: Theme.of(context).textTheme.bodySmall),
                  ),
                if (def.guiaCodigo != null) GuiaBoton(codigo: def.guiaCodigo!),
                const SizedBox(height: 8),
                for (final c in def.campos.where((c) => c.enFormulario)) ...[
                  _campo(c),
                  const SizedBox(height: 12),
                ],
                FilledButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  icon: const Icon(Icons.save),
                  label: Text(_guardando ? 'Guardando…' : 'Guardar'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Lo que deje vacío queda como "sin datos" (nunca como 0). La base valida las reglas y, si algo no cumple, '
                  'le explica por qué.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ]),
            ),
    );
  }

  Widget _campo(CampoDef c) {
    final etiqueta = '${c.etiqueta}${c.obligatorio ? ' *' : ''}${c.unidad != null ? ' (${c.unidad})' : ''}';
    if (c.soloLectura) {
      return InputDecorator(
        decoration: InputDecoration(labelText: c.etiqueta),
        child: Text(textoValor(c, _valores[c.clave] ?? widget.iniciales[c.clave])),
      );
    }
    switch (c.tipo) {
      case TipoCampo.texto:
      case TipoCampo.textoLargo:
      case TipoCampo.entero:
      case TipoCampo.decimal:
        final numerico = c.tipo == TipoCampo.entero || c.tipo == TipoCampo.decimal;
        return TextFormField(
          controller: _controlador(c.clave),
          minLines: c.tipo == TipoCampo.textoLargo ? 2 : 1,
          maxLines: c.tipo == TipoCampo.textoLargo ? 6 : 1,
          keyboardType: numerico ? const TextInputType.numberWithOptions(decimal: true, signed: true) : null,
          decoration: InputDecoration(labelText: etiqueta, helperText: c.ayuda, helperMaxLines: 3),
          validator: (t) {
            final v = (t ?? '').trim();
            if (c.obligatorio && v.isEmpty) return 'Obligatorio';
            if (v.isNotEmpty && c.tipo == TipoCampo.entero && int.tryParse(v) == null) return 'Número entero';
            if (v.isNotEmpty && c.tipo == TipoCampo.decimal && double.tryParse(v.replaceAll(',', '.')) == null) {
              return 'Número (use punto o coma)';
            }
            return null;
          },
        );
      case TipoCampo.opcion:
      case TipoCampo.naturaleza:
      case TipoCampo.calidad:
        final opciones = c.tipo == TipoCampo.naturaleza
            ? naturalezas
            : c.tipo == TipoCampo.calidad
                ? estadosCalidad
                : c.opciones;
        final actual = _valores[c.clave]?.toString();
        return DropdownButtonFormField<String>(
          value: opciones.contains(actual) ? actual : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: etiqueta, helperText: c.ayuda, helperMaxLines: 3),
          items: [
            if (!c.obligatorio) const DropdownMenuItem<String>(value: null, child: Text('sin datos')),
            for (final o in opciones) DropdownMenuItem(value: o, child: Text(etiquetaDe(o))),
          ],
          onChanged: (v) => setState(() => _valores[c.clave] = v),
          validator: (v) => c.obligatorio && v == null ? 'Obligatorio' : null,
        );
      case TipoCampo.booleano:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(c.etiqueta),
          subtitle: c.ayuda == null ? null : Text(c.ayuda!),
          value: _valores[c.clave] == true,
          onChanged: (v) => setState(() => _valores[c.clave] = v),
        );
      case TipoCampo.fecha:
      case TipoCampo.fechaHora:
        final actual = _valores[c.clave] == null ? null : DateTime.tryParse('${_valores[c.clave]}');
        return FormField<String>(
          validator: (_) => c.obligatorio && _valores[c.clave] == null ? 'Obligatorio' : null,
          builder: (estado) => InputDecorator(
            decoration: InputDecoration(labelText: etiqueta, helperText: c.ayuda, errorText: estado.errorText),
            child: Row(children: [
              Expanded(child: Text(actual == null ? 'sin fecha' : fechaCorta(actual, hora: c.tipo == TipoCampo.fechaHora))),
              IconButton(
                tooltip: 'Elegir fecha',
                icon: const Icon(Icons.calendar_month),
                onPressed: () async {
                  final base = actual?.toLocal() ?? DateTime.now();
                  final d = await showDatePicker(
                      context: context, initialDate: base, firstDate: DateTime(1990), lastDate: DateTime(2100));
                  if (d == null || !mounted) return;
                  var resultado = DateTime(d.year, d.month, d.day, base.hour, base.minute);
                  if (c.tipo == TipoCampo.fechaHora && mounted) {
                    final h = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
                    if (h != null) resultado = DateTime(d.year, d.month, d.day, h.hour, h.minute);
                  }
                  setState(() => _valores[c.clave] = resultado.toUtc().toIso8601String());
                  estado.didChange(_valores[c.clave] as String);
                },
              ),
              if (!c.obligatorio && actual != null)
                IconButton(
                  tooltip: 'Quitar fecha',
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => _valores[c.clave] = null),
                ),
            ]),
          ),
        );
      case TipoCampo.referencia:
        final clave = ClaveReferencia(c.refTabla!, c.refEtiqueta ?? 'nombre', _filtroTexto(c.refFiltro));
        final opciones = ref.watch(referenciasProvider(clave));
        return opciones.when(
          loading: () => InputDecorator(decoration: InputDecoration(labelText: etiqueta), child: const LinearProgressIndicator()),
          error: (e, _) => InputDecorator(decoration: InputDecoration(labelText: etiqueta), child: Text(mensajeError(e))),
          data: (lista) {
            final actual = _valores[c.clave]?.toString();
            final ids = lista.map((e) => e.key).toSet();
            return DropdownButtonFormField<String>(
              value: ids.contains(actual) ? actual : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: etiqueta,
                helperText: lista.isEmpty ? 'Aún no hay registros para elegir' : c.ayuda,
              ),
              items: [
                if (!c.obligatorio) const DropdownMenuItem<String>(value: null, child: Text('ninguno')),
                for (final o in lista) DropdownMenuItem(value: o.key, child: Text(o.value, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _valores[c.clave] = v),
              validator: (v) => c.obligatorio && v == null ? 'Obligatorio' : null,
            );
          },
        );
    }
  }
}
