import 'package:flutter/material.dart';

/// Etiqueta visible de la naturaleza del dato (DA-025). Nunca se oculta.
class EtiquetaNaturaleza extends StatelessWidget {
  const EtiquetaNaturaleza(this.naturaleza, {super.key});
  final String? naturaleza;
  @override
  Widget build(BuildContext context) => Chip(
        visualDensity: VisualDensity.compact,
        label: Text(naturaleza ?? 'sin naturaleza'),
      );
}

/// Muestra "sin datos" / "no calculable" en vez de 0.
String valorONo(num? v, {String unidad = '', String faltante = 'sin datos'}) =>
    v == null ? faltante : '${v.toString()}${unidad.isEmpty ? '' : ' $unidad'}';

const naturalezas = ['observado', 'medido', 'estimado', 'calculado', 'externo', 'pronosticado', 'validado'];

void mostrarMensaje(BuildContext context, String texto) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));

/// Vista estándar para listas vacías o errores.
class Vacio extends StatelessWidget {
  const Vacio(this.texto, {super.key});
  final String texto;
  @override
  Widget build(BuildContext context) =>
      Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(texto, textAlign: TextAlign.center)));
}
