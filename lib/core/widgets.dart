import 'package:flutter/material.dart';

/// Etiqueta visible de la naturaleza del dato (DA-025). Nunca se oculta.
class EtiquetaNaturaleza extends StatelessWidget {
  const EtiquetaNaturaleza(this.naturaleza, {super.key});
  final String? naturaleza;
  @override
  Widget build(BuildContext context) => Chip(
        visualDensity: VisualDensity.compact,
        avatar: const Icon(Icons.info_outline, size: 16),
        label: Text(naturaleza ?? 'sin naturaleza'),
      );
}

/// Muestra "sin datos" / "no calculable" en vez de 0.
String valorONo(num? v, {String unidad = '', String faltante = 'sin datos'}) {
  if (v == null) return faltante;
  final t = v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
  return '$t${unidad.isEmpty ? '' : ' $unidad'}';
}

const naturalezas = ['observado', 'medido', 'estimado', 'calculado', 'externo', 'pronosticado', 'validado'];

const estadosCalidad = [
  'pendiente',
  'registrado',
  'en_revision',
  'validado',
  'inconsistente',
  'rechazado',
  'corregido',
  'reemplazado',
  'no_disponible',
  'no_aplica',
];

void mostrarMensaje(BuildContext context, String texto) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));

/// Vista estándar para listas vacías o errores.
class Vacio extends StatelessWidget {
  const Vacio(this.texto, {super.key, this.icono = Icons.inbox_outlined});
  final String texto;
  final IconData icono;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icono, size: 40, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 8),
            Text(texto, textAlign: TextAlign.center),
          ]),
        ),
      );
}

/// Bloque con título dentro de una tarjeta (expedientes, tablero).
class Seccion extends StatelessWidget {
  const Seccion({super.key, required this.titulo, required this.hijos, this.icono, this.accion, this.color});
  final String titulo;
  final List<Widget> hijos;
  final IconData? icono;
  final Widget? accion;
  final Color? color;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              if (icono != null) ...[Icon(icono, size: 20, color: color), const SizedBox(width: 8)],
              Expanded(child: Text(titulo, style: Theme.of(context).textTheme.titleMedium)),
              if (accion != null) accion!,
            ]),
            const SizedBox(height: 6),
            ...hijos,
          ]),
        ),
      );
}

/// Chip de estado (el texto siempre acompaña al color: nunca color solo).
class ChipEstado extends StatelessWidget {
  const ChipEstado(this.texto, {super.key, this.icono});
  final String texto;
  final IconData? icono;
  @override
  Widget build(BuildContext context) => Chip(
        visualDensity: VisualDensity.compact,
        avatar: icono == null ? null : Icon(icono, size: 16),
        label: Text(texto),
      );
}

/// Pide un texto (motivo, nota). Devuelve null si se cancela.
Future<String?> pedirTexto(BuildContext context,
    {required String titulo, String etiqueta = '', String? ayuda, bool obligatorio = true, String inicial = ''}) {
  final c = TextEditingController(text: inicial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: TextField(
        controller: c,
        autofocus: true,
        minLines: 1,
        maxLines: 5,
        decoration: InputDecoration(labelText: etiqueta, helperText: ayuda, helperMaxLines: 3),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (obligatorio && c.text.trim().isEmpty) return;
            Navigator.pop(ctx, c.text.trim());
          },
          child: const Text('Aceptar'),
        ),
      ],
    ),
  );
}

/// Fecha corta legible (local).
String fechaCorta(Object? v, {bool hora = true}) {
  if (v == null) return 'sin fecha';
  final d = v is DateTime ? v : DateTime.tryParse('$v');
  if (d == null) return '$v';
  final l = d.toLocal();
  String dos(int n) => n.toString().padLeft(2, '0');
  final f = '${l.year}-${dos(l.month)}-${dos(l.day)}';
  return hora ? '$f ${dos(l.hour)}:${dos(l.minute)}' : f;
}

/// Barras horizontales simples (una serie, un color). Los valores van en texto,
/// nunca solo en color; un valor nulo se muestra "sin datos", no como barra vacía de 0.
class BarrasHorizontales extends StatelessWidget {
  const BarrasHorizontales({super.key, required this.datos, required this.color, this.unidad = '', this.alTocar});
  final List<MapEntry<String, num?>> datos;
  final Color color;
  final String unidad;
  final void Function(String etiqueta)? alTocar;

  @override
  Widget build(BuildContext context) {
    if (datos.isEmpty) return const Text('sin datos');
    final maximo = datos.map((e) => (e.value ?? 0).abs()).fold<num>(0, (a, b) => a > b ? a : b);
    final tema = Theme.of(context);
    return Column(
      children: [
        for (final d in datos)
          InkWell(
            onTap: alTocar == null ? null : () => alTocar!(d.key),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(width: 120, child: Text(d.key, overflow: TextOverflow.ellipsis, style: tema.textTheme.bodySmall)),
                Expanded(
                  child: LayoutBuilder(builder: (context, c) {
                    final v = d.value;
                    if (v == null) return Text('sin datos', style: tema.textTheme.bodySmall);
                    final ancho = maximo == 0 ? 0.0 : (v.abs() / maximo) * c.maxWidth;
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Tooltip(
                        message: '${d.key}: ${valorONo(v, unidad: unidad)}',
                        child: Container(
                          width: ancho < 2 ? 2 : ancho,
                          height: 14,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(width: 8),
                SizedBox(
                    width: 70,
                    child: Text(valorONo(d.value, unidad: unidad),
                        textAlign: TextAlign.right, style: tema.textTheme.bodySmall)),
              ]),
            ),
          ),
      ],
    );
  }
}

/// Serie temporal en columnas (una serie). Tocar o mantener muestra el valor.
class ColumnasTiempo extends StatelessWidget {
  const ColumnasTiempo({super.key, required this.datos, required this.color, this.unidad = '', this.alto = 120});
  final List<MapEntry<String, num>> datos;
  final Color color;
  final String unidad;
  final double alto;

  @override
  Widget build(BuildContext context) {
    if (datos.isEmpty) return const Padding(padding: EdgeInsets.all(8), child: Text('sin datos en el periodo'));
    final maximo = datos.map((e) => e.value).fold<num>(0, (a, b) => a > b ? a : b);
    final tema = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: alto,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final d in datos)
            Expanded(
              child: Tooltip(
                triggerMode: TooltipTriggerMode.tap,
                message: '${d.key}: ${valorONo(d.value, unidad: unidad)}',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Container(
                    height: maximo == 0 ? 2 : ((d.value / maximo) * (alto - 4)).clamp(2, alto).toDouble(),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
      const Divider(height: 1),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(datos.first.key, style: tema.textTheme.bodySmall),
        Text('máx. ${valorONo(maximo, unidad: unidad)}', style: tema.textTheme.bodySmall),
        Text(datos.last.key, style: tema.textTheme.bodySmall),
      ]),
    ]);
  }
}

/// Número destacado del tablero con su unidad y nota (sin datos ≠ 0).
class Cifra extends StatelessWidget {
  const Cifra({super.key, required this.titulo, required this.valor, this.nota, this.icono, this.color, this.alTocar});
  final String titulo;
  final String valor;
  final String? nota;
  final IconData? icono;
  final Color? color;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: alTocar,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              if (icono != null) Icon(icono, size: 18, color: color),
              if (icono != null) const SizedBox(width: 6),
              Expanded(child: Text(titulo, style: tema.textTheme.labelMedium, overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 6),
            Text(valor, style: tema.textTheme.headlineSmall),
            if (nota != null) Text(nota!, style: tema.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }
}
