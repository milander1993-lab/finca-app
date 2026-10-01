/// Unidad espacial: 'potrero' (máx. 6 por finca, D-012) o 'division' (temporal, A1, A2…).
class Unidad {
  const Unidad({required this.id, required this.tipo, required this.nombre, this.parentId, this.superficieHa, this.superficieNaturaleza});
  final String id;
  final String tipo;
  final String nombre;
  final String? parentId;
  final num? superficieHa;
  final String? superficieNaturaleza;

  bool get esPotrero => tipo == 'potrero';

  factory Unidad.desdeMapa(Map<String, dynamic> m) => Unidad(
        id: m['id'] as String,
        tipo: (m['tipo'] as String?) ?? 'sin tipo',
        nombre: (m['nombre'] as String?) ?? 'sin nombre',
        parentId: m['parent_id'] as String?,
        superficieHa: m['superficie_ha'] as num?,
        superficieNaturaleza: m['superficie_naturaleza'] as String?,
      );
}

/// Fila de `v_alertas_ocupacion`. La causa nunca se infiere (D-012).
class OcupacionVista {
  const OcupacionVista({
    required this.id,
    required this.unidadId,
    required this.unidadNombre,
    required this.loteNombre,
    required this.entrada,
    this.salida,
    required this.horas,
    required this.excede,
    this.mensaje,
  });
  final String id;
  final String unidadId;
  final String unidadNombre;
  final String loteNombre;
  final DateTime entrada;
  final DateTime? salida;
  final num horas;
  final bool excede;
  final String? mensaje;
  bool get abierta => salida == null;

  factory OcupacionVista.desdeMapa(Map<String, dynamic> m) => OcupacionVista(
        id: m['ocupacion_id'] as String,
        unidadId: m['unidad_id'] as String,
        unidadNombre: (m['unidad_nombre'] as String?) ?? '—',
        loteNombre: (m['lote_nombre'] as String?) ?? '—',
        entrada: DateTime.parse(m['entrada_en'] as String),
        salida: m['salida_en'] == null ? null : DateTime.parse(m['salida_en'] as String),
        horas: (m['horas_ocupadas'] as num?) ?? 0,
        excede: (m['excede_limite'] as bool?) ?? false,
        mensaje: m['mensaje'] as String?,
      );
}

/// Fila de `v_aforos_resumen`. Valores null = no calculable (nunca 0).
class AforoResumen {
  const AforoResumen({
    required this.aforoId,
    required this.unidadId,
    required this.fecha,
    required this.naturaleza,
    this.nPuntos,
    this.nPuntosConMs,
    this.msPct,
    this.aguaPct,
    this.msPctMin,
    this.msPctMax,
    this.msGM2,
    this.msKgHa,
    required this.estado,
    this.advertencia,
  });
  final String aforoId;
  final String unidadId;
  final DateTime fecha;
  final String naturaleza;
  final int? nPuntos;
  final int? nPuntosConMs;
  final num? msPct;
  final num? aguaPct;
  final num? msPctMin;
  final num? msPctMax;
  final num? msGM2;
  final num? msKgHa;
  final String estado;
  final String? advertencia;

  factory AforoResumen.desdeMapa(Map<String, dynamic> m) => AforoResumen(
        aforoId: m['aforo_id'] as String,
        unidadId: m['unidad_id'] as String,
        fecha: DateTime.parse(m['fecha_aforo'] as String),
        naturaleza: m['naturaleza'] as String,
        nPuntos: m['n_puntos'] as int?,
        nPuntosConMs: m['n_puntos_con_ms'] as int?,
        msPct: m['ms_pct'] as num?,
        aguaPct: m['agua_pct'] as num?,
        msPctMin: m['ms_pct_min_punto'] as num?,
        msPctMax: m['ms_pct_max_punto'] as num?,
        msGM2: m['ms_g_por_m2'] as num?,
        msKgHa: m['ms_kg_por_ha'] as num?,
        estado: m['estado_ms_pct'] as String,
        advertencia: m['advertencia'] as String?,
      );
}

class MuestraAforo {
  const MuestraAforo({required this.id, required this.punto, this.areaM2, this.mfG, this.msG, this.estadoCalidad});
  final String id;
  final int punto;
  final num? areaM2;
  final num? mfG;
  final num? msG;
  final String? estadoCalidad;

  /// %MS y %agua del punto (solo si hay MF y MS).
  num? get msPct => (mfG == null || msG == null) ? null : (msG! / mfG! * 100);
  num? get aguaPct => msPct == null ? null : 100 - msPct!;

  factory MuestraAforo.desdeMapa(Map<String, dynamic> m) => MuestraAforo(
        id: m['id'] as String,
        punto: m['punto'] as int,
        areaM2: m['area_muestra_m2'] as num?,
        mfG: m['materia_fresca_g'] as num?,
        msG: m['materia_seca_g'] as num?,
        estadoCalidad: m['estado_calidad'] as String?,
      );
}
