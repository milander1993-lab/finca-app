/// Animal integrado (§71): un solo registro, relacionado con lote, pesajes, QR, evidencias.
class Animal {
  const Animal({
    required this.id,
    required this.numeroInterno,
    this.categoria,
    this.sexo,
    this.estado,
    this.pesoUltimo,
    this.pesoUltimoNaturaleza,
    this.pesoUltimoFecha,
  });

  final String id;
  final String numeroInterno;
  final String? categoria; // texto libre: lo que no tenga nombre se escribe a mano
  final String? sexo;
  final String? estado;
  final num? pesoUltimo; // null = sin datos (nunca 0)
  final String? pesoUltimoNaturaleza;
  final DateTime? pesoUltimoFecha;

  factory Animal.desdeMapa(Map<String, dynamic> m) => Animal(
        id: m['id'] as String,
        numeroInterno: m['numero_interno'] as String,
        categoria: m['categoria'] as String?,
        sexo: m['sexo'] as String?,
        estado: m['estado'] as String?,
        pesoUltimo: m['peso_ultimo'] as num?,
        pesoUltimoNaturaleza: m['peso_ultimo_naturaleza'] as String?,
        pesoUltimoFecha: m['peso_ultimo_fecha'] == null ? null : DateTime.parse(m['peso_ultimo_fecha'] as String),
      );
}

class Pesaje {
  const Pesaje({required this.id, required this.fecha, required this.valorKg, required this.naturaleza, this.metodo, this.estadoCalidad});
  final String id;
  final DateTime fecha;
  final num valorKg;
  final String naturaleza;
  final String? metodo;
  final String? estadoCalidad;

  factory Pesaje.desdeMapa(Map<String, dynamic> m) => Pesaje(
        id: m['id'] as String,
        fecha: DateTime.parse(m['fecha_pesaje'] as String),
        valorKg: m['valor'] as num,
        naturaleza: m['naturaleza'] as String,
        metodo: m['metodo'] as String?,
        estadoCalidad: m['estado_calidad'] as String?,
      );
}
