-- ============================================================================
-- 00016_nucleo_integral.sql — Arquitectura completa de 8 niveles en la base de datos.
-- ADITIVA e idempotente. Requiere 00002–00015.
--
-- Fuente: Prompt Maestro de Continuidad §7–§60 y Documento Maestro V4/V5.
--  Nivel 1  base física/ambiental : fuentes_agua, mediciones_ambientales (clima/lluvia),
--                                   muestras_suelo + resultados_suelo (§23–§25)
--  Nivel 2  capacidad de manejo    : infraestructuras (§22), recursos (equipos, herramientas,
--                                   insumos, capacidad humana)
--  Nivel 3  sistemas productivos   : sistemas_productivos, eventos_sanitarios,
--                                   eventos_reproductivos, produccion_leche, entregas_leche,
--                                   movimientos_economicos (§19–§21, D-024), especies,
--                                   lotes_vivero, establecimientos (§21)
--  Nivel 4  procesos/actividades   : actividades con máquina de estados (§26)
--  Nivel 5  monitoreo/indicadores  : indicadores_def (solo fórmulas acordadas), alertas (§28)
--  Nivel 6  análisis               : hallazgos (señal/hallazgo/hipótesis/diagnóstico, §30–§31)
--  Nivel 7  decisiones             : recomendaciones, alternativas, decisiones (§27, §32, §33)
--  Nivel 8  mejora continua        : aprendizajes (§34)
--  Transversal: observaciones, evidencias (Drive), misión/visión de la finca,
--               tareas conectadas automáticamente, tablero, búsqueda.
--
-- Reglas: nada se borra (anular), todo se audita, ningún valor de la finca se inventa,
-- ninguna frecuencia técnica se inventa (las tareas automáticas sin fecha definida quedan
-- 'pendiente' sin fecha), una señal/alerta no afirma causa, recomendación ≠ decisión,
-- ejecutada ≠ verificada ≠ cerrada, entrega ≠ pago, observación ≠ diagnóstico.
-- ============================================================================
DO $$ BEGIN
  IF to_regclass('public.ia_interacciones') IS NULL OR to_regprocedure('public.exportar_finca(uuid)') IS NULL THEN
    RAISE EXCEPTION '00016 requiere 00012 y 00015.';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 0. Finca: misión y visión (las escribe el usuario; vacío = "sin definir")
-- ---------------------------------------------------------------------------
ALTER TABLE public.fincas ADD COLUMN IF NOT EXISTS mision text;
ALTER TABLE public.fincas ADD COLUMN IF NOT EXISTS vision text;
ALTER TABLE public.fincas ADD COLUMN IF NOT EXISTS datos_declarados_en timestamptz;

-- ---------------------------------------------------------------------------
-- 1. Tablas (las columnas estándar se agregan en el bloque 2)
-- ---------------------------------------------------------------------------
-- NIVEL 1 ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.fuentes_agua (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id uuid NOT NULL REFERENCES public.fincas(id),
  tipo text NOT NULL CHECK (tipo IN ('nacimiento','escorrentia','zona_concentracion','humedal','canal',
                                     'conduccion','captacion','almacenamiento','distribucion','uso','otro')),
  nombre text NOT NULL CHECK (btrim(nombre) <> ''),
  unidad_id uuid REFERENCES public.unidades_espaciales(id),
  latitud numeric(10,7) CHECK (latitud IS NULL OR latitud BETWEEN -90 AND 90),
  longitud numeric(10,7) CHECK (longitud IS NULL OR longitud BETWEEN -180 AND 180),
  precision_m numeric(8,2) CHECK (precision_m IS NULL OR precision_m >= 0),
  metodo_ubicacion text,
  estado text NOT NULL DEFAULT 'pendiente_verificacion'
    CHECK (estado IN ('existente','operativo','fuera_de_servicio','proyectado','pendiente_verificacion')),
  conservacion boolean NOT NULL DEFAULT false,
  naturaleza public.naturaleza_dato NOT NULL DEFAULT 'observado',
  descripcion text
);

CREATE TABLE IF NOT EXISTS public.mediciones_ambientales (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id uuid NOT NULL REFERENCES public.fincas(id),
  variable text NOT NULL CHECK (variable IN ('precipitacion','temperatura','humedad_relativa','caudal','otra')),
  variable_otra text,
  fecha_hecho timestamptz NOT NULL,
  valor numeric(14,4) NOT NULL,
  unidad text NOT NULL CHECK (btrim(unidad) <> ''),
  naturaleza public.naturaleza_dato NOT NULL,
  fuente text,                              -- pluviómetro propio, IDEAM, modelo, etc.
  metodo text,
  unidad_id uuid REFERENCES public.unidades_espaciales(id),
  fuente_agua_id uuid REFERENCES public.fuentes_agua(id),
  estado_calidad public.estado_calidad_dato NOT NULL DEFAULT 'registrado',
  nota_calidad text,
  CHECK (variable <> 'otra' OR btrim(coalesce(variable_otra,'')) <> ''),
  CHECK (variable <> 'precipitacion' OR (unidad = 'mm' AND valor >= 0))
);

CREATE TABLE IF NOT EXISTS public.muestras_suelo (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id uuid NOT NULL REFERENCES public.fincas(id),
  unidad_id uuid REFERENCES public.unidades_espaciales(id),
  etiqueta text NOT NULL CHECK (btrim(etiqueta) <> ''),
  fecha_hecho timestamptz NOT NULL,
  numero_puntos integer CHECK (numero_puntos IS NULL OR numero_puntos > 0),
  profundidad_cm numeric(6,2) CHECK (profundidad_cm IS NULL OR profundidad_cm > 0),
  metodo text,
  laboratorio text,
  estado text NOT NULL DEFAULT 'tomada' CHECK (estado IN ('tomada','enviada','resultado_recibido','anulada_muestra')),
  observaciones text
);

CREATE TABLE IF NOT EXISTS public.resultados_suelo (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id uuid NOT NULL REFERENCES public.fincas(id),
  muestra_id uuid NOT NULL REFERENCES public.muestras_suelo(id),
  parametro text NOT NULL CHECK (parametro IN ('ph_agua','fosforo_bray_ii','saturacion_aluminio','aluminio',
                                               'materia_organica','calcio','magnesio','potasio','textura','otro')),
  parametro_otro text,
  valor numeric(14,4),
  valor_texto text,                          -- p. ej. textura
  unidad text,
  metodo_laboratorio text,
  naturaleza public.naturaleza_dato NOT NULL DEFAULT 'externo',
  fuente text,                               -- informe del laboratorio
  estado_calidad public.estado_calidad_dato NOT NULL DEFAULT 'registrado',
  nota_calidad text,
  CHECK (valor IS NOT NULL OR btrim(coalesce(valor_texto,'')) <> ''),
  CHECK (parametro <> 'otro' OR btrim(coalesce(parametro_otro,'')) <> '')
);

-- NIVEL 2 ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.infraestructuras (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id uuid NOT NULL REFERENCES public.fincas(id),
  tipo text NOT NULL CHECK (btrim(tipo) <> ''),                 -- vivienda, cerca, corral… (catálogo abierto)
  nombre text NOT NULL CHECK (btrim(nombre) <> ''),
  unidad_id uuid REFERENCES public.unidades_espaciales(id),
  estado text NOT NULL DEFAULT 'pendiente_verificacion'
    CHECK (estado IN ('existente','operativo','fuera_de_servicio','mantenimiento','reparacion','reparado',
                      'proyectado','en_construccion','pendiente_verificacion')),
  descripcion text,
  latitud numeric(10,7), longitud numeric(10,7),
  naturaleza public.naturaleza_dato NOT NULL DEFAULT 'observado'
);

CREATE TABLE IF NOT EXISTS public.recursos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id uuid NOT NULL REFERENCES public.fincas(id),
  clase text NOT NULL CHECK (clase IN ('equipo','herramienta','insumo','material','capacidad_humana','otro')),
  nombre text NOT NULL CHECK (btrim(nombre) <> ''),
  cantidad numeric(14,3) CHECK (cantidad IS NULL OR cantidad >= 0),   -- vacío = sin datos
  unidad text,
  estado text NOT NULL DEFAULT 'disponible'
    CHECK (estado IN ('requerido','disponible','reservado','recibido','entregado','utilizado',
                      'operativo','fuera_de_servicio','mantenimiento','pendiente_verificacion')),
  infraestructura_id uuid REFERENCES public.infraestructuras(id),
  descripcion text,
  naturaleza public.naturaleza_dato NOT NULL DEFAULT 'observado'
);

-- NIVEL 3 ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.sistemas_productivos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id uuid NOT NULL REFERENCES public.fincas(id),
  tipo text NOT NULL CHECK (tipo IN ('ganaderia','pasturas','pancoger','vivero','silvopastoril','banco_forraje',
                                     'compostaje','conservacion','otro')),
  nombre text NOT NULL CHECK (btrim(nombre) <> ''),
  unidad_id uuid REFERENCES public.unidades_espaciales(id),
  superficie_ha numeric(12,4) CHECK (superficie_ha IS NULL OR superficie_ha > 0),
  superficie_naturaleza public.naturaleza_dato,
  estado text NOT NULL DEFAULT 'activo' CHECK (estado IN ('activo','proyectado','en_establecimiento','suspendido','pendiente_verificacion')),
  descripcion text,
  CHECK (superficie_ha IS NULL OR superficie_naturaleza IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS public.eventos_sanitarios (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id uuid NOT NULL REFERENCES public.fincas(id),
  animal_id uuid REFERENCES public.animales(id),
  lote_id uuid REFERENCES public.lotes_ganaderos(id),
  tipo text NOT NULL CHECK (tipo IN ('observacion','ectoparasitos','endoparasitos','vacunacion','desparasitacion',
                                     'tratamiento','diagnostico','examen','control','seguimiento')),
  etapa text NOT NULL DEFAULT 'observacion'
    CHECK (etapa IN ('observacion','revision','diagnostico_profesional','tratamiento_autorizado','seguimiento','verificacion','cerrado')),
  fecha_hecho timestamptz NOT NULL,
  descripcion text NOT NULL CHECK (btrim(descripcion) <> ''),
  producto text,
  dosis text,
  via text,
  profesional text,                          -- quién diagnostica/autoriza (cuando corresponde)
  resultado text,
  naturaleza public.naturaleza_dato NOT NULL DEFAULT 'observado',
  estado_calidad public.estado_calidad_dato NOT NULL DEFAULT 'registrado',
  nota_calidad text,
  CHECK (animal_id IS NOT NULL OR lote_id IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS public.eventos_reproductivos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id uuid NOT NULL REFERENCES public.fincas(id),
  animal_id uuid NOT NULL REFERENCES public.animales(id),
  tipo text NOT NULL CHECK (tipo IN ('servicio','palpacion','diagnostico_gestacion','parto','destete','secado','otro')),
  fecha_hecho timestamptz NOT NULL,
  resultado text,                            -- p. ej. gestante / vacía (lo escribe quien diagnostica)
  responsable text,
  cria_animal_id uuid REFERENCES public.animales(id),
  descripcion text,
  naturaleza public.naturaleza_dato NOT NULL DEFAULT 'observado',
  estado_calidad public.estado_calidad_dato NOT NULL DEFAULT 'registrado',
  nota_calidad text
);

CREATE TABLE IF NOT EXISTS public.produccion_leche (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id uuid NOT NULL REFERENCES public.fincas(id),
  animal_id uuid REFERENCES public.animales(id),
  lote_id uuid REFERENCES public.lotes_ganaderos(id),
  fecha_hecho timestamptz NOT NULL,
  litros numeric(10,2) NOT NULL CHECK (litros >= 0),
  turno text,
  naturaleza public.naturaleza_dato NOT NULL,
  estado_calidad public.estado_calidad_dato NOT NULL DEFAULT 'registrado',
  nota_calidad text
);

CREATE TABLE IF NOT EXISTS public.entregas_leche (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id uuid NOT NULL REFERENCES public.fincas(id),
  fecha_hecho timestamptz NOT NULL,
  litros numeric(10,2) NOT NULL CHECK (litros > 0),
  comprador text,
  estado text NOT NULL DEFAULT 'entregada' CHECK (estado IN ('entregada','vendida','por_cobrar','pagada','rechazada')),
  valor_cop numeric(14,2) CHECK (valor_cop IS NULL OR valor_cop >= 0),
  fecha_pago timestamptz,
  naturaleza public.naturaleza_dato NOT NULL DEFAULT 'medido',
  descripcion text,
  CHECK (estado <> 'pagada' OR fecha_pago IS NOT NULL)        -- entrega ≠ pago (D-024)
);

CREATE TABLE IF NOT EXISTS public.movimientos_economicos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id uuid NOT NULL REFERENCES public.fincas(id),
  clase text NOT NULL CHECK (clase IN ('costo','gasto','ingreso','pago','cuenta_por_cobrar','cuenta_por_pagar')),
  concepto text NOT NULL CHECK (btrim(concepto) <> ''),
  valor_cop numeric(14,2) NOT NULL CHECK (valor_cop >= 0),
  fecha_hecho timestamptz NOT NULL,
  sistema text,                              -- a qué sistema productivo se atribuye (si se sabe)
  sistema_id uuid REFERENCES public.sistemas_productivos(id),
  soporte text,                              -- factura / recibo (la evidencia va a Drive)
  naturaleza public.naturaleza_dato NOT NULL DEFAULT 'medido',
  descripcion text
);

CREATE TABLE IF NOT EXISTS public.especies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id uuid NOT NULL REFERENCES public.fincas(id),
  nombre_comun text NOT NULL CHECK (btrim(nombre_comun) <> ''),
  nombre_cientifico text,
  usos text,
  propagacion text,                          -- no se asume estaca (§21)
  descripcion text
);

CREATE TABLE IF NOT EXISTS public.lotes_vivero (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id uuid NOT NULL REFERENCES public.fincas(id),
  especie_id uuid NOT NULL REFERENCES public.especies(id),
  codigo text NOT NULL CHECK (btrim(codigo) <> ''),
  origen text,                               -- semilla, planta madre, compra…
  planta_madre text,
  metodo_propagacion text,
  fecha_inicio timestamptz NOT NULL,
  cantidad_inicial integer CHECK (cantidad_inicial IS NULL OR cantidad_inicial >= 0),
  cantidad_actual integer CHECK (cantidad_actual IS NULL OR cantidad_actual >= 0),
  unidad_id uuid REFERENCES public.unidades_espaciales(id),
  estado text NOT NULL DEFAULT 'en_propagacion' CHECK (estado IN ('en_propagacion','listo','trasplantado','perdido','cerrado')),
  naturaleza public.naturaleza_dato NOT NULL DEFAULT 'observado',
  descripcion text
);

CREATE TABLE IF NOT EXISTS public.establecimientos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id uuid NOT NULL REFERENCES public.fincas(id),
  especie_id uuid NOT NULL REFERENCES public.especies(id),
  lote_vivero_id uuid REFERENCES public.lotes_vivero(id),
  sistema_id uuid REFERENCES public.sistemas_productivos(id),
  unidad_id uuid REFERENCES public.unidades_espaciales(id),
  fecha_hecho timestamptz NOT NULL,
  cantidad integer CHECK (cantidad IS NULL OR cantidad > 0),
  etapa text NOT NULL DEFAULT 'establecimiento'
    CHECK (etapa IN ('siembra','establecimiento','crecimiento','produccion','mantenimiento','perdido','reemplazado')),
  condicion text,                            -- condición observada
  sobrevivencia integer CHECK (sobrevivencia IS NULL OR sobrevivencia >= 0),
  naturaleza public.naturaleza_dato NOT NULL DEFAULT 'observado',
  descripcion text
);

-- NIVEL 4 ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.actividades (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id uuid NOT NULL REFERENCES public.fincas(id),
  titulo text NOT NULL CHECK (btrim(titulo) <> ''),
  proceso text,                               -- pastoreo, sanidad, mantenimiento…
  tipo text NOT NULL DEFAULT 'actividad' CHECK (tipo IN ('actividad','tarea','seguimiento','verificacion')),
  descripcion text,
  estado text NOT NULL DEFAULT 'programada' CHECK (estado IN (
    'programada','disponible','iniciada','pausada','reanudada','ejecutada','requiere_verificacion','verificada','cerrada',
    'bloqueada','parcial','pendiente','reprogramada','cancelada','no_aplica')),
  origen_tipo text NOT NULL DEFAULT 'manual' CHECK (origen_tipo IN (
    'manual','alerta','decision','recomendacion','ocupacion','aforo','sanidad','reproduccion','infraestructura',
    'suelo','recurso','seguimiento','hallazgo','aprendizaje')),
  origen_id uuid,
  objeto_tipo text,                           -- tabla del objeto sobre el que se actúa
  objeto_id uuid,
  animal_id uuid REFERENCES public.animales(id),
  lote_id uuid REFERENCES public.lotes_ganaderos(id),
  unidad_id uuid REFERENCES public.unidades_espaciales(id),
  responsable text,
  verificador text,
  fecha_programada timestamptz,
  fecha_inicio timestamptz,
  fecha_ejecucion timestamptz,
  fecha_verificacion timestamptz,
  fecha_cierre timestamptz,
  resultado text,
  verificacion text,
  verificado_por uuid REFERENCES auth.users(id),
  requiere_seguimiento boolean NOT NULL DEFAULT false,
  nota_estado text,
  guia_codigo text,
  clave_auto text                             -- evita duplicar tareas automáticas
);

-- NIVEL 5 ------------------------------------------------------------------
-- Catálogo global de indicadores: SOLO fórmulas acordadas en la arquitectura.
CREATE TABLE IF NOT EXISTS public.indicadores_def (
  codigo text PRIMARY KEY,
  nombre text NOT NULL,
  nivel integer NOT NULL CHECK (nivel BETWEEN 1 AND 8),
  proposito text NOT NULL,
  formula text NOT NULL,
  unidad text NOT NULL,
  datos_origen text NOT NULL,
  frecuencia text NOT NULL DEFAULT 'pendiente de definir (34.6)',
  criterio text NOT NULL DEFAULT 'sin criterio de comparación aprobado (34.17)',
  fuente text NOT NULL,
  version integer NOT NULL DEFAULT 1,
  estado text NOT NULL CHECK (estado IN ('activo','conceptual')),
  limitaciones text NOT NULL
);
INSERT INTO public.indicadores_def (codigo,nombre,nivel,proposito,formula,unidad,datos_origen,fuente,estado,limitaciones) VALUES
 ('ms_pct','Materia seca del forraje',5,'Saber qué parte del pasto es materia seca','%MS = Σ masa seca ÷ Σ masa fresca × 100','%','aforo_muestras (puntos completos)','Prompt Maestro §18 (fórmula cerrada)','activo','Excluye puntos rechazados o sin secar; sin puntos completos = no calculable'),
 ('agua_pct','Agua del forraje',5,'Saber cuánta agua tiene el pasto','%agua = 100 − %MS','%','aforo_muestras','CHG-014','activo','Depende de %MS'),
 ('ms_kg_ha','Materia seca por hectárea (por puntos)',5,'Expresar la masa seca muestreada por superficie','Σ MS (g) ÷ Σ área (m²) × 10','kg MS/ha','aforo_muestras','CHG-014 (1 g/m² = 10 kg/ha)','activo','No es oferta del potrero completo: el método de aforo 34.6 sigue pendiente'),
 ('demanda_ms','Demanda de materia seca del lote',5,'Estimar cuánta materia seca necesita un lote por día','Σ peso vivo × % consumo MS ÷ 100','kg MS/día','pesajes vigentes + criterio ms_pct_peso_vivo','Prompt Maestro §18 / 00009','activo','Sin criterio con fuente o sin peso de algún animal = no calculable. Oferta − demanda ≠ consumo real'),
 ('horas_ocupacion','Horas de ocupación de un área',5,'Controlar el máximo aprobado de 2 días','salida (o ahora) − entrada','h','ocupaciones_pastoreo','D-012','activo','Superar el límite genera alerta, no indica causa'),
 ('dias_descanso','Días de descanso de un área',5,'Conocer el descanso entre ocupaciones','nuevo ingreso − salida anterior (misma unidad)','días','ocupaciones_pastoreo','Prompt Maestro §17','activo','Solo calculable si hay salida anterior registrada'),
 ('lluvia_l_m2','Lluvia en litros por metro cuadrado',1,'Traducir la lluvia a volumen por superficie','1 mm sobre 1 m² = 1 L','L/m²','mediciones_ambientales (precipitación)','Prompt Maestro §25','activo','Volumen potencial ≠ escorrentía ≠ captado ≠ almacenado ≠ disponible'),
 ('leche_litros','Litros producidos',5,'Seguir la producción de leche del periodo','Σ litros del periodo','L','produccion_leche','Prompt Maestro §19','activo','Producción ≠ entrega ≠ pago'),
 ('costo_litro','Costo por litro',5,'Relacionar costos productivos con la leche','costos productivos atribuibles ÷ litros del mismo periodo','COP/L','movimientos_economicos (costo) + produccion_leche','Prompt Maestro §19','conceptual','La atribución de costos (34.4) no está definida: se muestra como referencia, no como resultado validado'),
 ('peso_ultimo','Peso último por animal',5,'Ver el último peso válido','último pesaje no rechazado','kg','pesajes','00002','activo','Un animal puede existir sin peso: sin pesaje = sin datos')
ON CONFLICT (codigo) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.alertas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id uuid NOT NULL REFERENCES public.fincas(id),
  tipo text NOT NULL,
  regla text NOT NULL,                        -- qué regla la generó (o 'manual')
  mensaje text NOT NULL CHECK (btrim(mensaje) <> ''),
  objeto_tipo text,
  objeto_id uuid,
  estado text NOT NULL DEFAULT 'generada' CHECK (estado IN ('generada','pendiente','revisada','en_analisis','atendida',
                     'descartada','convertida_actividad','convertida_decision','convertida_hallazgo','cerrada')),
  destino_tipo text,
  destino_id uuid,
  nota text,
  clave text NOT NULL                         -- un hecho = una alerta (sin duplicados incontrolados)
);

-- NIVEL 6 ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.hallazgos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id uuid NOT NULL REFERENCES public.fincas(id),
  tipo text NOT NULL CHECK (tipo IN ('senal','hallazgo','hipotesis','diagnostico')),
  titulo text NOT NULL CHECK (btrim(titulo) <> ''),
  descripcion text,
  objeto_tipo text, objeto_id uuid,
  origen_tipo text, origen_id uuid,           -- alerta, indicador, ia, manual
  datos_usados jsonb,
  metodo text,
  incertidumbre text,
  estado text NOT NULL DEFAULT 'preliminar' CHECK (estado IN ('preliminar','en_revision','validado','descartado','reemplazado')),
  validado_por text,                          -- profesional/persona que valida
  validado_en timestamptz
);

-- NIVEL 7 ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.recomendaciones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id uuid NOT NULL REFERENCES public.fincas(id),
  titulo text NOT NULL CHECK (btrim(titulo) <> ''),
  descripcion text,
  origen text NOT NULL DEFAULT 'humano' CHECK (origen IN ('humano','ia','regla')),
  hallazgo_id uuid REFERENCES public.hallazgos(id),
  ia_interaccion_id uuid REFERENCES public.ia_interacciones(id),
  datos_usados jsonb,
  metodo text, criterio text, criterio_version text, fuente text, incertidumbre text,
  estado text NOT NULL DEFAULT 'generada' CHECK (estado IN ('generada','revision','aceptada','modificada','rechazada','reemplazada')),
  nota_revision text
);

CREATE TABLE IF NOT EXISTS public.alternativas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id uuid NOT NULL REFERENCES public.fincas(id),
  recomendacion_id uuid NOT NULL REFERENCES public.recomendaciones(id),
  descripcion text NOT NULL CHECK (btrim(descripcion) <> ''),
  condiciones text, ventajas text, desventajas text, recursos text
);

CREATE TABLE IF NOT EXISTS public.decisiones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id uuid NOT NULL REFERENCES public.fincas(id),
  titulo text NOT NULL CHECK (btrim(titulo) <> ''),
  descripcion text,
  resolucion text NOT NULL DEFAULT 'aceptar' CHECK (resolucion IN ('aceptar','rechazar','modificar','posponer',
                     'solicitar_informacion','seleccionar_alternativa','no_intervencion','otra')),
  recomendacion_id uuid REFERENCES public.recomendaciones(id),
  alternativa_id uuid REFERENCES public.alternativas(id),
  hallazgo_id uuid REFERENCES public.hallazgos(id),
  -- §33: todo resultado usado para decidir conserva esto
  datos_usados text, metodo text, criterio text, criterio_version text, fuente text, evidencia text,
  condicion text,                              -- decisión condicional: no ejecuta hasta comprobarla
  accion_titulo text,                          -- actividad que se programa al aprobar
  accion_fecha timestamptz,
  accion_responsable text,
  estado text NOT NULL DEFAULT 'borrador' CHECK (estado IN ('borrador','revision','aprobada','programada','ejecutandose',
                     'cumplida','verificada','cerrada')),
  aprobada_por uuid REFERENCES auth.users(id),
  aprobada_en timestamptz,
  resultado text,
  verificacion text
);

-- NIVEL 8 ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.aprendizajes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id uuid NOT NULL REFERENCES public.fincas(id),
  titulo text NOT NULL CHECK (btrim(titulo) <> ''),
  experiencia text,
  evaluacion text,
  aprendizaje text,
  propuesta_mejora text,
  implementacion text,
  validacion text,
  origen_tipo text, origen_id uuid,            -- actividad, decisión, incidente…
  estado text NOT NULL DEFAULT 'experiencia' CHECK (estado IN ('experiencia','evaluacion','aprendizaje','propuesta',
                     'revision','aprobada','implementada','nueva_version','validada','conocimiento','descartada'))
);

-- TRANSVERSAL --------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.observaciones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id uuid NOT NULL REFERENCES public.fincas(id),
  objeto_tipo text NOT NULL,
  objeto_id uuid NOT NULL,
  fecha_hecho timestamptz NOT NULL DEFAULT now(),
  texto text NOT NULL CHECK (btrim(texto) <> ''),
  naturaleza public.naturaleza_dato NOT NULL DEFAULT 'observado'
);

CREATE TABLE IF NOT EXISTS public.evidencias (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id uuid NOT NULL REFERENCES public.fincas(id),
  objeto_tipo text NOT NULL,
  objeto_id uuid NOT NULL,
  tipo text NOT NULL CHECK (tipo IN ('foto','pdf','documento','informe_laboratorio','factura','otro')),
  descripcion text NOT NULL CHECK (btrim(descripcion) <> ''),
  enlace text,                                 -- enlace de Google Drive (D-008)
  drive_file_id text,
  estado text NOT NULL DEFAULT 'pendiente_sincronizacion' CHECK (estado IN ('pendiente_sincronizacion','subida','error')),
  fecha_hecho timestamptz,
  CHECK (estado <> 'subida' OR (enlace IS NOT NULL OR drive_file_id IS NOT NULL))
);

-- Incidentes técnicos: se agregan los estados del Prompt Maestro §27 (los anteriores siguen válidos)
ALTER TABLE public.incidentes_tecnicos DROP CONSTRAINT IF EXISTS incidentes_tecnicos_estado_check;
ALTER TABLE public.incidentes_tecnicos ADD CONSTRAINT incidentes_tecnicos_estado_check CHECK (estado IN (
  'abierto','en_analisis','resuelto','cerrado',
  'reportado','diagnostico','solucion_propuesta','intervencion_requerida','corrigiendo','pruebas','verificado'));
ALTER TABLE public.incidentes_tecnicos ADD COLUMN IF NOT EXISTS modulo text;
ALTER TABLE public.incidentes_tecnicos ADD COLUMN IF NOT EXISTS pantalla text;
ALTER TABLE public.incidentes_tecnicos ADD COLUMN IF NOT EXISTS version_app text;
ALTER TABLE public.incidentes_tecnicos ADD COLUMN IF NOT EXISTS conectividad text;

-- ---------------------------------------------------------------------------
-- 2. Columnas estándar, autoría, auditoría, anular≠borrar, sincronización y RLS
-- ---------------------------------------------------------------------------
DO $$
DECLARE t text;
  tablas text[] := ARRAY['fuentes_agua','mediciones_ambientales','muestras_suelo','resultados_suelo',
    'infraestructuras','recursos','sistemas_productivos','eventos_sanitarios','eventos_reproductivos',
    'produccion_leche','entregas_leche','movimientos_economicos','especies','lotes_vivero','establecimientos',
    'actividades','alertas','hallazgos','recomendaciones','alternativas','decisiones','aprendizajes',
    'observaciones','evidencias'];
BEGIN
  FOREACH t IN ARRAY tablas LOOP
    EXECUTE format('ALTER TABLE public.%I
      ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
      ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now(),
      ADD COLUMN IF NOT EXISTS created_by uuid REFERENCES auth.users(id),
      ADD COLUMN IF NOT EXISTS updated_by uuid REFERENCES auth.users(id),
      ADD COLUMN IF NOT EXISTS version integer NOT NULL DEFAULT 1,
      ADD COLUMN IF NOT EXISTS is_deleted boolean NOT NULL DEFAULT false,
      ADD COLUMN IF NOT EXISTS motivo_anulacion text,
      ADD COLUMN IF NOT EXISTS sincronizada_en timestamptz', t);
    EXECUTE format('CREATE INDEX IF NOT EXISTS ix_%s_finca ON public.%I (finca_id, created_at DESC) WHERE NOT is_deleted', t, t);
    EXECUTE format('DROP TRIGGER IF EXISTS t10_sellar_autoria ON public.%I', t);
    EXECUTE format('CREATE TRIGGER t10_sellar_autoria BEFORE INSERT OR UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.sellar_autoria()', t);
    EXECUTE format('DROP TRIGGER IF EXISTS t12_sincronizacion_ins ON public.%I', t);
    EXECUTE format('CREATE TRIGGER t12_sincronizacion_ins BEFORE INSERT ON public.%I FOR EACH ROW EXECUTE FUNCTION public.sellar_sincronizacion()', t);
    EXECUTE format('DROP TRIGGER IF EXISTS t12_sincronizacion_upd ON public.%I', t);
    EXECUTE format('CREATE TRIGGER t12_sincronizacion_upd BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.proteger_sincronizacion()', t);
    EXECUTE format('DROP TRIGGER IF EXISTS t20_timestamps ON public.%I', t);
    EXECUTE format('CREATE TRIGGER t20_timestamps BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.actualizar_timestamps()', t);
    EXECUTE format('DROP TRIGGER IF EXISTS t30_bloquear_delete ON public.%I', t);
    EXECUTE format('CREATE TRIGGER t30_bloquear_delete BEFORE DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.bloquear_delete()', t);
    EXECUTE format('DROP TRIGGER IF EXISTS t90_auditar ON public.%I', t);
    EXECUTE format('CREATE TRIGGER t90_auditar AFTER INSERT OR UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.auditar_cambio()', t);
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
      EXECUTE format('REVOKE DELETE, TRUNCATE ON public.%I FROM authenticated', t);
      EXECUTE format('GRANT SELECT, INSERT, UPDATE ON public.%I TO authenticated', t);
      EXECUTE format('DROP POLICY IF EXISTS p16_%s_select ON public.%I', t, t);
      EXECUTE format('CREATE POLICY p16_%s_select ON public.%I FOR SELECT TO authenticated USING (public.es_miembro_finca(finca_id))', t, t);
      EXECUTE format('DROP POLICY IF EXISTS p16_%s_insert ON public.%I', t, t);
      EXECUTE format('CREATE POLICY p16_%s_insert ON public.%I FOR INSERT TO authenticated WITH CHECK (public.es_miembro_finca(finca_id))', t, t);
      EXECUTE format('DROP POLICY IF EXISTS p16_%s_update ON public.%I', t, t);
      EXECUTE format('CREATE POLICY p16_%s_update ON public.%I FOR UPDATE TO authenticated USING (public.es_miembro_finca(finca_id)) WITH CHECK (public.es_miembro_finca(finca_id))', t, t);
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
      EXECUTE format('REVOKE ALL ON public.%I FROM anon', t);
    END IF;
  END LOOP;
END $$;

-- Índices que dependen de is_deleted (tareas automáticas y alertas: un hecho = un registro)
CREATE UNIQUE INDEX IF NOT EXISTS ux_actividades_clave_auto
  ON public.actividades (finca_id, clave_auto) WHERE clave_auto IS NOT NULL AND NOT is_deleted;
CREATE UNIQUE INDEX IF NOT EXISTS ux_alertas_clave ON public.alertas (finca_id, clave) WHERE NOT is_deleted;

-- Calidad de dato: estado problemático exige nota (misma regla de 00008)
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['mediciones_ambientales','resultados_suelo','eventos_sanitarios','eventos_reproductivos','produccion_leche'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS t40_calidad ON public.%I', t);
    EXECUTE format('CREATE TRIGGER t40_calidad BEFORE INSERT OR UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.calidad_dato_reglas()', t);
  END LOOP;
END $$;

-- Indicadores: catálogo de lectura
ALTER TABLE public.indicadores_def ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    EXECUTE 'GRANT SELECT ON public.indicadores_def TO authenticated';
    EXECUTE 'DROP POLICY IF EXISTS p16_indicadores_select ON public.indicadores_def';
    EXECUTE 'CREATE POLICY p16_indicadores_select ON public.indicadores_def FOR SELECT TO authenticated USING (true)';
    -- La finca: sus miembros pueden escribir misión y visión
    EXECUTE 'GRANT UPDATE (mision, vision) ON public.fincas TO authenticated';
    EXECUTE 'DROP POLICY IF EXISTS p16_fincas_update ON public.fincas';
    EXECUTE 'CREATE POLICY p16_fincas_update ON public.fincas FOR UPDATE TO authenticated USING (public.es_miembro_finca(id)) WITH CHECK (public.es_miembro_finca(id))';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON public.indicadores_def FROM anon';
  END IF;
END $$;

-- Anular exige motivo (anular ≠ borrar; queda en auditoría)
CREATE OR REPLACE FUNCTION public.anular_exige_motivo()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF NEW.is_deleted AND NOT OLD.is_deleted AND btrim(coalesce(NEW.motivo_anulacion,'')) = '' THEN
    RAISE EXCEPTION 'anular exige escribir el motivo' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['fuentes_agua','mediciones_ambientales','muestras_suelo','resultados_suelo',
    'infraestructuras','recursos','sistemas_productivos','eventos_sanitarios','eventos_reproductivos',
    'produccion_leche','entregas_leche','movimientos_economicos','especies','lotes_vivero','establecimientos',
    'actividades','alertas','hallazgos','recomendaciones','alternativas','decisiones','aprendizajes',
    'observaciones','evidencias'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS t15_anular_motivo ON public.%I', t);
    EXECUTE format('CREATE TRIGGER t15_anular_motivo BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.anular_exige_motivo()', t);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- 3. Tareas conectadas automáticamente (helpers)
-- ---------------------------------------------------------------------------
-- Crea una tarea automática una sola vez por hecho (clave). Sin fecha definida → 'pendiente'.
CREATE OR REPLACE FUNCTION public.tarea_auto(
  p_finca uuid, p_clave text, p_titulo text, p_proceso text, p_origen_tipo text, p_origen_id uuid,
  p_objeto_tipo text, p_objeto_id uuid, p_fecha timestamptz DEFAULT NULL, p_guia text DEFAULT NULL,
  p_animal uuid DEFAULT NULL, p_lote uuid DEFAULT NULL, p_unidad uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  INSERT INTO public.actividades (finca_id, titulo, proceso, tipo, estado, origen_tipo, origen_id,
                                  objeto_tipo, objeto_id, fecha_programada, guia_codigo, clave_auto,
                                  animal_id, lote_id, unidad_id)
  VALUES (p_finca, p_titulo, p_proceso, 'tarea', CASE WHEN p_fecha IS NULL THEN 'pendiente' ELSE 'programada' END,
          p_origen_tipo, p_origen_id, p_objeto_tipo, p_objeto_id, p_fecha, p_guia, p_clave, p_animal, p_lote, p_unidad)
  ON CONFLICT (finca_id, clave_auto) WHERE clave_auto IS NOT NULL AND NOT is_deleted DO NOTHING;
END $$;

-- Marca como ejecutada (→ requiere verificación) la tarea automática abierta de ese hecho.
CREATE OR REPLACE FUNCTION public.tarea_auto_ejecutada(p_finca uuid, p_clave text, p_resultado text)
RETURNS void LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  UPDATE public.actividades
     SET estado = 'ejecutada', resultado = p_resultado
   WHERE finca_id = p_finca AND clave_auto = p_clave AND NOT is_deleted
     AND estado IN ('programada','disponible','pendiente','iniciada','reanudada','parcial','reprogramada');
END $$;

-- ---------------------------------------------------------------------------
-- 4. Máquina de estados de actividades (§26): ejecutada ≠ verificada ≠ cerrada
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.actividades_reglas()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE
  permitidas text[];
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.estado NOT IN ('programada','pendiente','disponible') THEN
      RAISE EXCEPTION 'una actividad nueva empieza programada, pendiente o disponible' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.estado = 'programada' AND NEW.fecha_programada IS NULL THEN
      NEW.estado := 'pendiente';      -- sin fecha no se inventa una
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.estado = OLD.estado THEN RETURN NEW; END IF;
  permitidas := CASE OLD.estado
    WHEN 'programada'  THEN ARRAY['disponible','iniciada','ejecutada','reprogramada','cancelada','bloqueada','pendiente','no_aplica']
    WHEN 'pendiente'   THEN ARRAY['programada','disponible','iniciada','ejecutada','cancelada','bloqueada','no_aplica']
    WHEN 'disponible'  THEN ARRAY['iniciada','ejecutada','reprogramada','cancelada','bloqueada']
    WHEN 'iniciada'    THEN ARRAY['pausada','ejecutada','parcial','bloqueada','cancelada']
    WHEN 'pausada'     THEN ARRAY['reanudada','cancelada']
    WHEN 'reanudada'   THEN ARRAY['pausada','ejecutada','parcial']
    WHEN 'parcial'     THEN ARRAY['iniciada','ejecutada','reprogramada']
    WHEN 'bloqueada'   THEN ARRAY['pendiente','programada','cancelada']
    WHEN 'reprogramada' THEN ARRAY['programada','disponible','iniciada','ejecutada']
    WHEN 'ejecutada'   THEN ARRAY['requiere_verificacion']
    WHEN 'requiere_verificacion' THEN ARRAY['verificada','iniciada']
    WHEN 'verificada'  THEN ARRAY['cerrada']
    WHEN 'cancelada'   THEN ARRAY['cerrada']
    WHEN 'no_aplica'   THEN ARRAY['cerrada']
    ELSE ARRAY[]::text[] END;
  IF NOT (NEW.estado = ANY(permitidas)) THEN
    RAISE EXCEPTION 'la actividad no puede pasar de "%" a "%"', OLD.estado, NEW.estado USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.estado IN ('bloqueada','reprogramada','cancelada','parcial','no_aplica') AND btrim(coalesce(NEW.nota_estado,'')) = '' THEN
    RAISE EXCEPTION 'el estado "%" exige explicar el motivo (nota_estado)', NEW.estado USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.estado = 'iniciada' AND NEW.fecha_inicio IS NULL THEN NEW.fecha_inicio := now(); END IF;
  IF NEW.estado = 'ejecutada' THEN
    IF btrim(coalesce(NEW.resultado,'')) = '' THEN
      RAISE EXCEPTION 'para marcar ejecutada escriba el resultado (qué se hizo)' USING ERRCODE = 'check_violation';
    END IF;
    NEW.fecha_ejecucion := coalesce(NEW.fecha_ejecucion, now());
    NEW.estado := 'requiere_verificacion';       -- ejecutada → requiere verificación (§26)
  END IF;
  IF NEW.estado = 'verificada' THEN
    IF btrim(coalesce(NEW.verificacion,'')) = '' THEN
      RAISE EXCEPTION 'verificar exige escribir cómo se comprobó el resultado' USING ERRCODE = 'check_violation';
    END IF;
    NEW.fecha_verificacion := now();
    NEW.verificado_por := auth.uid();
  END IF;
  IF NEW.estado = 'cerrada' THEN NEW.fecha_cierre := now(); END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS t50_reglas ON public.actividades;
CREATE TRIGGER t50_reglas BEFORE INSERT OR UPDATE ON public.actividades FOR EACH ROW EXECUTE FUNCTION public.actividades_reglas();

-- Conexiones: actividad ↔ decisión ↔ alerta ↔ infraestructura ↔ seguimiento
CREATE OR REPLACE FUNCTION public.actividades_conectar()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE
  v_total int; v_hechas int; v_verif int;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.estado = OLD.estado THEN RETURN NULL; END IF;

  IF NEW.origen_tipo = 'decision' AND NEW.origen_id IS NOT NULL THEN
    SELECT count(*) FILTER (WHERE estado NOT IN ('cancelada','no_aplica')),
           count(*) FILTER (WHERE estado IN ('requiere_verificacion','verificada','cerrada')),
           count(*) FILTER (WHERE estado IN ('verificada','cerrada'))
      INTO v_total, v_hechas, v_verif
      FROM public.actividades WHERE origen_tipo = 'decision' AND origen_id = NEW.origen_id AND NOT is_deleted;
    IF NEW.estado IN ('iniciada','requiere_verificacion') THEN
      UPDATE public.decisiones SET estado = 'ejecutandose'
       WHERE id = NEW.origen_id AND estado IN ('aprobada','programada');
    END IF;
    IF v_total > 0 AND v_hechas = v_total THEN
      UPDATE public.decisiones SET estado = 'ejecutandose' WHERE id = NEW.origen_id AND estado IN ('aprobada','programada');
      UPDATE public.decisiones SET estado = 'cumplida' WHERE id = NEW.origen_id AND estado = 'ejecutandose';
    END IF;
    IF v_total > 0 AND v_verif = v_total THEN
      UPDATE public.decisiones SET estado = 'verificada' WHERE id = NEW.origen_id AND estado = 'cumplida';
    END IF;
  END IF;

  IF NEW.origen_tipo = 'alerta' AND NEW.origen_id IS NOT NULL AND NEW.estado = 'verificada' THEN
    UPDATE public.alertas SET estado = 'atendida', nota = coalesce(nota,'') || ' Atendida por actividad verificada.'
     WHERE id = NEW.origen_id AND estado = 'convertida_actividad';
  END IF;

  IF NEW.origen_tipo = 'infraestructura' AND NEW.objeto_id IS NOT NULL AND NEW.estado = 'verificada' THEN
    -- falla → alerta → reparación → verificación → retorno a servicio (§22)
    UPDATE public.infraestructuras SET estado = 'operativo'
     WHERE id = NEW.objeto_id AND estado IN ('reparado','reparacion','mantenimiento','fuera_de_servicio');
  END IF;

  IF NEW.estado = 'verificada' AND NEW.requiere_seguimiento THEN
    PERFORM public.tarea_auto(NEW.finca_id, 'seguimiento:' || NEW.id, 'Seguimiento: ' || NEW.titulo, NEW.proceso,
                              'seguimiento', NEW.id, NEW.objeto_tipo, NEW.objeto_id, NULL, NEW.guia_codigo,
                              NEW.animal_id, NEW.lote_id, NEW.unidad_id);
  END IF;
  RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS t60_conectar ON public.actividades;
CREATE TRIGGER t60_conectar AFTER INSERT OR UPDATE ON public.actividades FOR EACH ROW EXECUTE FUNCTION public.actividades_conectar();

-- ---------------------------------------------------------------------------
-- 5. Decisiones (§27, §33): aprobar exige trazabilidad; aprobada → actividad programada
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.decisiones_reglas()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE permitidas text[];
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.estado NOT IN ('borrador','revision') THEN
      RAISE EXCEPTION 'una decisión nueva empieza en borrador o revisión' USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.estado = OLD.estado THEN RETURN NEW; END IF;
  permitidas := CASE OLD.estado
    WHEN 'borrador' THEN ARRAY['revision','aprobada']
    WHEN 'revision' THEN ARRAY['borrador','aprobada']
    WHEN 'aprobada' THEN ARRAY['programada','ejecutandose','cumplida']
    WHEN 'programada' THEN ARRAY['ejecutandose','cumplida']
    WHEN 'ejecutandose' THEN ARRAY['cumplida']
    WHEN 'cumplida' THEN ARRAY['verificada']
    WHEN 'verificada' THEN ARRAY['cerrada']
    ELSE ARRAY[]::text[] END;
  IF NOT (NEW.estado = ANY(permitidas)) THEN
    RAISE EXCEPTION 'la decisión no puede pasar de "%" a "%"', OLD.estado, NEW.estado USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.estado = 'aprobada' THEN
    IF btrim(coalesce(NEW.datos_usados,'')) = '' OR btrim(coalesce(NEW.metodo,'')) = ''
       OR btrim(coalesce(NEW.criterio,'')) = '' OR btrim(coalesce(NEW.fuente,'')) = ''
       OR btrim(coalesce(NEW.evidencia,'')) = '' OR btrim(coalesce(NEW.criterio_version,'')) = '' THEN
      RAISE EXCEPTION 'aprobar exige datos usados, método, criterio, versión del criterio, fuente y evidencia (§33). Si no aplica, escriba "no aplica".'
        USING ERRCODE = 'check_violation';
    END IF;
    NEW.aprobada_por := auth.uid();
    NEW.aprobada_en := now();
  END IF;
  IF NEW.estado = 'verificada' AND btrim(coalesce(NEW.verificacion,'')) = '' AND
     NOT EXISTS (SELECT 1 FROM public.actividades a WHERE a.origen_tipo = 'decision' AND a.origen_id = NEW.id
                 AND a.estado IN ('verificada','cerrada') AND NOT a.is_deleted) THEN
    RAISE EXCEPTION 'verificar la decisión exige escribir la verificación' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS t50_reglas ON public.decisiones;
CREATE TRIGGER t50_reglas BEFORE INSERT OR UPDATE ON public.decisiones FOR EACH ROW EXECUTE FUNCTION public.decisiones_reglas();

CREATE OR REPLACE FUNCTION public.decisiones_conectar()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF NEW.estado = 'aprobada' AND OLD.estado IS DISTINCT FROM 'aprobada' AND btrim(coalesce(NEW.accion_titulo,'')) <> '' THEN
    IF btrim(coalesce(NEW.condicion,'')) <> '' THEN
      -- decisión condicional: primero se comprueba la condición (sin ejecutar acciones sensibles)
      PERFORM public.tarea_auto(NEW.finca_id, 'decision_condicion:' || NEW.id,
        'Comprobar condición: ' || NEW.condicion, 'decisiones', 'decision', NEW.id, 'decisiones', NEW.id, NULL);
    END IF;
    PERFORM public.tarea_auto(NEW.finca_id, 'decision:' || NEW.id, NEW.accion_titulo, 'decisiones', 'decision', NEW.id,
                              'decisiones', NEW.id, NEW.accion_fecha);
    UPDATE public.actividades SET responsable = NEW.accion_responsable
     WHERE finca_id = NEW.finca_id AND clave_auto = 'decision:' || NEW.id AND responsable IS NULL;
    UPDATE public.decisiones SET estado = 'programada' WHERE id = NEW.id AND estado = 'aprobada';
  END IF;
  IF NEW.recomendacion_id IS NOT NULL AND NEW.estado = 'aprobada' AND OLD.estado IS DISTINCT FROM 'aprobada' THEN
    UPDATE public.recomendaciones SET estado = 'aceptada', nota_revision = coalesce(nota_revision,'') || ' Decisión aprobada.'
     WHERE id = NEW.recomendacion_id AND estado IN ('generada','revision');
  END IF;
  RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS t60_conectar ON public.decisiones;
CREATE TRIGGER t60_conectar AFTER UPDATE ON public.decisiones FOR EACH ROW EXECUTE FUNCTION public.decisiones_conectar();

-- Recomendaciones: recomendación ≠ decisión
CREATE OR REPLACE FUNCTION public.recomendaciones_reglas()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE permitidas text[];
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.estado <> 'generada' THEN RAISE EXCEPTION 'una recomendación nueva queda "generada"' USING ERRCODE = 'check_violation'; END IF;
    RETURN NEW;
  END IF;
  IF NEW.estado = OLD.estado THEN RETURN NEW; END IF;
  permitidas := CASE OLD.estado
    WHEN 'generada' THEN ARRAY['revision','aceptada','modificada','rechazada','reemplazada']
    WHEN 'revision' THEN ARRAY['aceptada','modificada','rechazada','reemplazada']
    WHEN 'modificada' THEN ARRAY['revision','aceptada','rechazada','reemplazada']
    ELSE ARRAY['reemplazada'] END;
  IF NOT (NEW.estado = ANY(permitidas)) THEN
    RAISE EXCEPTION 'la recomendación no puede pasar de "%" a "%"', OLD.estado, NEW.estado USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.estado IN ('rechazada','modificada','reemplazada') AND btrim(coalesce(NEW.nota_revision,'')) = '' THEN
    RAISE EXCEPTION 'explique la revisión (nota_revision)' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS t50_reglas ON public.recomendaciones;
CREATE TRIGGER t50_reglas BEFORE INSERT OR UPDATE ON public.recomendaciones FOR EACH ROW EXECUTE FUNCTION public.recomendaciones_reglas();

-- Hallazgos: un diagnóstico validado exige quién lo valida (observación ≠ diagnóstico)
CREATE OR REPLACE FUNCTION public.hallazgos_reglas()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF NEW.estado = 'validado' THEN
    IF btrim(coalesce(NEW.validado_por,'')) = '' THEN
      RAISE EXCEPTION 'validar exige indicar quién valida (y para diagnósticos, el profesional)' USING ERRCODE = 'check_violation';
    END IF;
    NEW.validado_en := coalesce(NEW.validado_en, now());
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS t50_reglas ON public.hallazgos;
CREATE TRIGGER t50_reglas BEFORE INSERT OR UPDATE ON public.hallazgos FOR EACH ROW EXECUTE FUNCTION public.hallazgos_reglas();

-- ---------------------------------------------------------------------------
-- 6. Tareas automáticas desde los procesos de campo
-- ---------------------------------------------------------------------------
-- Pastoreo: al entrar un lote se programa la salida al límite aprobado (D-012: 48 h).
CREATE OR REPLACE FUNCTION public.ocupacion_tareas()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE v_unidad text; v_lote text;
BEGIN
  SELECT nombre INTO v_unidad FROM public.unidades_espaciales WHERE id = NEW.unidad_id;
  SELECT nombre INTO v_lote FROM public.lotes_ganaderos WHERE id = NEW.lote_id;
  IF TG_OP = 'INSERT' AND NEW.salida_en IS NULL AND NOT NEW.is_deleted THEN
    PERFORM public.tarea_auto(NEW.finca_id, 'ocupacion_salida:' || NEW.id,
      'Sacar lote ' || coalesce(v_lote,'?') || ' de ' || coalesce(v_unidad,'?') || ' (límite aprobado de ocupación)',
      'pastoreo', 'ocupacion', NEW.id, 'ocupaciones_pastoreo', NEW.id,
      NEW.entrada_en + make_interval(hours => public.ocupacion_max_horas()), 'ocupacion_pastoreo',
      NULL, NEW.lote_id, NEW.unidad_id);
  END IF;
  IF NEW.salida_en IS NOT NULL AND (TG_OP = 'INSERT' OR OLD.salida_en IS NULL) THEN
    PERFORM public.tarea_auto_ejecutada(NEW.finca_id, 'ocupacion_salida:' || NEW.id,
      'Salida registrada el ' || to_char(NEW.salida_en AT TIME ZONE 'America/Bogota', 'YYYY-MM-DD HH24:MI'));
  END IF;
  RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS t60_tareas ON public.ocupaciones_pastoreo;
CREATE TRIGGER t60_tareas AFTER INSERT OR UPDATE ON public.ocupaciones_pastoreo FOR EACH ROW EXECUTE FUNCTION public.ocupacion_tareas();

-- Aforo: completar puntos y materia seca (tras el secado)
CREATE OR REPLACE FUNCTION public.aforo_tareas()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE v_aforo uuid; v_finca uuid; v_total int; v_ms int; v_unidad text;
BEGIN
  IF TG_TABLE_NAME = 'aforos' THEN
    v_aforo := NEW.id; v_finca := NEW.finca_id;
    SELECT nombre INTO v_unidad FROM public.unidades_espaciales WHERE id = NEW.unidad_id;
    IF TG_OP = 'INSERT' AND NEW.materia_seca_g IS NULL THEN
      PERFORM public.tarea_auto(v_finca, 'aforo_completar:' || v_aforo,
        'Completar aforo de ' || coalesce(v_unidad,'?') || ': puntos y materia seca tras el secado',
        'pastoreo', 'aforo', v_aforo, 'aforos', v_aforo, NULL, 'aforo_materia_seca', NULL, NULL, NEW.unidad_id);
    END IF;
    RETURN NULL;
  END IF;
  v_aforo := NEW.aforo_id; v_finca := NEW.finca_id;
  SELECT count(*), count(*) FILTER (WHERE materia_seca_g IS NOT NULL) INTO v_total, v_ms
    FROM public.aforo_muestras WHERE aforo_id = v_aforo AND NOT is_deleted;
  IF v_total > 0 AND v_total = v_ms THEN
    PERFORM public.tarea_auto_ejecutada(v_finca, 'aforo_completar:' || v_aforo,
      v_total || ' punto(s) con materia fresca y seca registradas');
  END IF;
  RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS t60_tareas ON public.aforos;
CREATE TRIGGER t60_tareas AFTER INSERT ON public.aforos FOR EACH ROW EXECUTE FUNCTION public.aforo_tareas();
DROP TRIGGER IF EXISTS t60_tareas ON public.aforo_muestras;
CREATE TRIGGER t60_tareas AFTER INSERT OR UPDATE ON public.aforo_muestras FOR EACH ROW EXECUTE FUNCTION public.aforo_tareas();

-- Infraestructura: falla → alerta → reparación → verificación → retorno a servicio
CREATE OR REPLACE FUNCTION public.infraestructura_tareas()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE v_clave text;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.estado = OLD.estado THEN RETURN NULL; END IF;
  v_clave := 'infra_reparar:' || NEW.id || ':' || NEW.version;
  IF NEW.estado IN ('fuera_de_servicio','reparacion','mantenimiento') THEN
    INSERT INTO public.alertas (finca_id, tipo, regla, mensaje, objeto_tipo, objeto_id, clave)
    VALUES (NEW.finca_id, 'infraestructura', 'infraestructura_estado',
            NEW.nombre || ' está en estado "' || replace(NEW.estado,'_',' ') || '". La causa no se infiere.',
            'infraestructuras', NEW.id, 'infra:' || NEW.id || ':' || NEW.version)
    ON CONFLICT (finca_id, clave) WHERE NOT is_deleted DO NOTHING;
    PERFORM public.tarea_auto(NEW.finca_id, 'infra_reparar:' || NEW.id,
      CASE NEW.estado WHEN 'mantenimiento' THEN 'Mantenimiento: ' ELSE 'Reparar: ' END || NEW.nombre,
      'mantenimiento', 'infraestructura', NEW.id, 'infraestructuras', NEW.id, NULL, NULL, NULL, NULL, NEW.unidad_id);
  END IF;
  IF NEW.estado = 'reparado' THEN
    PERFORM public.tarea_auto_ejecutada(NEW.finca_id, 'infra_reparar:' || NEW.id, 'Marcada como reparada');
  END IF;
  IF NEW.estado = 'operativo' THEN
    -- una recurrencia futura es un nuevo incidente: se libera la clave de la tarea cerrada
    UPDATE public.actividades SET clave_auto = clave_auto || ':' || id
     WHERE finca_id = NEW.finca_id AND clave_auto = 'infra_reparar:' || NEW.id
       AND estado IN ('verificada','cerrada','cancelada','no_aplica');
  END IF;
  RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS t60_tareas ON public.infraestructuras;
CREATE TRIGGER t60_tareas AFTER INSERT OR UPDATE ON public.infraestructuras FOR EACH ROW EXECUTE FUNCTION public.infraestructura_tareas();

-- Sanidad: observación → revisión → diagnóstico profesional → tratamiento autorizado → seguimiento → verificación
CREATE OR REPLACE FUNCTION public.sanidad_reglas()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE orden text[] := ARRAY['observacion','revision','diagnostico_profesional','tratamiento_autorizado','seguimiento','verificacion','cerrado'];
BEGIN
  IF TG_OP = 'UPDATE' AND array_position(orden, NEW.etapa) < array_position(orden, OLD.etapa) THEN
    RAISE EXCEPTION 'la etapa sanitaria no retrocede (registre un evento nuevo)' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.etapa IN ('diagnostico_profesional','tratamiento_autorizado') AND btrim(coalesce(NEW.profesional,'')) = '' THEN
    RAISE EXCEPTION 'diagnóstico y tratamiento exigen indicar el profesional que diagnostica/autoriza (observación ≠ diagnóstico)'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS t50_reglas ON public.eventos_sanitarios;
CREATE TRIGGER t50_reglas BEFORE INSERT OR UPDATE ON public.eventos_sanitarios FOR EACH ROW EXECUTE FUNCTION public.sanidad_reglas();

CREATE OR REPLACE FUNCTION public.sanidad_tareas()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF NEW.etapa = 'observacion' AND (TG_OP = 'INSERT') THEN
    PERFORM public.tarea_auto(NEW.finca_id, 'sanidad_revisar:' || NEW.id,
      'Revisar observación sanitaria: ' || left(NEW.descripcion, 80), 'sanidad', 'sanidad', NEW.id,
      'eventos_sanitarios', NEW.id, NULL, 'observacion_sanitaria', NEW.animal_id, NEW.lote_id, NULL);
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.etapa <> OLD.etapa THEN
    IF OLD.etapa = 'observacion' THEN
      PERFORM public.tarea_auto_ejecutada(NEW.finca_id, 'sanidad_revisar:' || NEW.id, 'Pasó a etapa ' || NEW.etapa);
    END IF;
    IF NEW.etapa = 'tratamiento_autorizado' THEN
      PERFORM public.tarea_auto(NEW.finca_id, 'sanidad_seguimiento:' || NEW.id,
        'Seguimiento del tratamiento: ' || left(NEW.descripcion, 80), 'sanidad', 'sanidad', NEW.id,
        'eventos_sanitarios', NEW.id, NULL, NULL, NEW.animal_id, NEW.lote_id, NULL);
    END IF;
    IF NEW.etapa IN ('verificacion','cerrado') THEN
      PERFORM public.tarea_auto_ejecutada(NEW.finca_id, 'sanidad_seguimiento:' || NEW.id, 'Evento en etapa ' || NEW.etapa);
    END IF;
  END IF;
  RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS t60_tareas ON public.eventos_sanitarios;
CREATE TRIGGER t60_tareas AFTER INSERT OR UPDATE ON public.eventos_sanitarios FOR EACH ROW EXECUTE FUNCTION public.sanidad_tareas();

-- Reproducción: servicio → (pendiente) diagnóstico de gestación; parto → registrar la cría.
-- No se inventan días: las tareas quedan "pendiente" sin fecha (frecuencias 34.6).
CREATE OR REPLACE FUNCTION public.reproduccion_tareas()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE v_num text;
BEGIN
  SELECT numero_interno INTO v_num FROM public.animales WHERE id = NEW.animal_id;
  IF NEW.tipo = 'servicio' THEN
    PERFORM public.tarea_auto(NEW.finca_id, 'repro_diagnostico:' || NEW.id,
      'Diagnóstico de gestación de ' || coalesce(v_num,'?') || ' (servicio del ' || to_char(NEW.fecha_hecho,'YYYY-MM-DD') || ')',
      'reproduccion', 'reproduccion', NEW.id, 'eventos_reproductivos', NEW.id, NULL, NULL, NEW.animal_id, NULL, NULL);
  END IF;
  IF NEW.tipo IN ('palpacion','diagnostico_gestacion') THEN
    UPDATE public.actividades a SET estado = 'ejecutada', resultado = 'Registrado: ' || NEW.tipo || coalesce(' — ' || NEW.resultado, '')
     WHERE a.finca_id = NEW.finca_id AND a.animal_id = NEW.animal_id AND a.clave_auto LIKE 'repro_diagnostico:%'
       AND a.estado IN ('pendiente','programada','disponible','iniciada','reanudada','parcial','reprogramada');
  END IF;
  IF NEW.tipo = 'parto' AND NEW.cria_animal_id IS NULL THEN
    PERFORM public.tarea_auto(NEW.finca_id, 'repro_cria:' || NEW.id,
      'Registrar la cría nacida de ' || coalesce(v_num,'?'), 'reproduccion', 'reproduccion', NEW.id,
      'eventos_reproductivos', NEW.id, NULL, NULL, NEW.animal_id, NULL, NULL);
  END IF;
  IF NEW.tipo = 'parto' AND NEW.cria_animal_id IS NOT NULL THEN
    PERFORM public.tarea_auto_ejecutada(NEW.finca_id, 'repro_cria:' || NEW.id, 'Cría registrada');
  END IF;
  RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS t60_tareas ON public.eventos_reproductivos;
CREATE TRIGGER t60_tareas AFTER INSERT OR UPDATE ON public.eventos_reproductivos FOR EACH ROW EXECUTE FUNCTION public.reproduccion_tareas();

-- Suelo: tomada → enviar al laboratorio → registrar resultados
CREATE OR REPLACE FUNCTION public.suelo_tareas()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF TG_TABLE_NAME = 'resultados_suelo' THEN
    PERFORM public.tarea_auto_ejecutada(NEW.finca_id, 'suelo_resultados:' || NEW.muestra_id, 'Resultados registrados');
    UPDATE public.muestras_suelo SET estado = 'resultado_recibido' WHERE id = NEW.muestra_id AND estado IN ('tomada','enviada');
    RETURN NULL;
  END IF;
  IF TG_OP = 'INSERT' AND NEW.estado = 'tomada' THEN
    PERFORM public.tarea_auto(NEW.finca_id, 'suelo_enviar:' || NEW.id, 'Enviar muestra de suelo ' || NEW.etiqueta || ' al laboratorio',
      'suelo', 'suelo', NEW.id, 'muestras_suelo', NEW.id, NULL, 'muestreo_suelo', NULL, NULL, NEW.unidad_id);
  END IF;
  IF NEW.estado IN ('enviada','resultado_recibido') AND (TG_OP = 'INSERT' OR OLD.estado = 'tomada') THEN
    PERFORM public.tarea_auto_ejecutada(NEW.finca_id, 'suelo_enviar:' || NEW.id, 'Muestra enviada');
    IF NEW.estado = 'enviada' THEN
      PERFORM public.tarea_auto(NEW.finca_id, 'suelo_resultados:' || NEW.id, 'Registrar resultados de laboratorio de ' || NEW.etiqueta,
        'suelo', 'suelo', NEW.id, 'muestras_suelo', NEW.id, NULL, NULL, NULL, NULL, NEW.unidad_id);
    END IF;
  END IF;
  RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS t60_tareas ON public.muestras_suelo;
CREATE TRIGGER t60_tareas AFTER INSERT OR UPDATE ON public.muestras_suelo FOR EACH ROW EXECUTE FUNCTION public.suelo_tareas();
DROP TRIGGER IF EXISTS t60_tareas ON public.resultados_suelo;
CREATE TRIGGER t60_tareas AFTER INSERT ON public.resultados_suelo FOR EACH ROW EXECUTE FUNCTION public.suelo_tareas();

-- Recursos requeridos → conseguir
CREATE OR REPLACE FUNCTION public.recurso_tareas()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF NEW.estado = 'requerido' AND (TG_OP = 'INSERT' OR OLD.estado <> 'requerido') THEN
    PERFORM public.tarea_auto(NEW.finca_id, 'recurso:' || NEW.id, 'Conseguir: ' || NEW.nombre,
      'recursos', 'recurso', NEW.id, 'recursos', NEW.id, NULL);
  END IF;
  IF NEW.estado IN ('disponible','recibido','entregado') AND TG_OP = 'UPDATE' AND OLD.estado = 'requerido' THEN
    PERFORM public.tarea_auto_ejecutada(NEW.finca_id, 'recurso:' || NEW.id, 'Recurso ' || NEW.estado);
  END IF;
  RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS t60_tareas ON public.recursos;
CREATE TRIGGER t60_tareas AFTER INSERT OR UPDATE ON public.recursos FOR EACH ROW EXECUTE FUNCTION public.recurso_tareas();

-- ---------------------------------------------------------------------------
-- 7. Alertas automáticas (reglas aprobadas; ninguna afirma causa)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.generar_alertas(p_finca uuid)
RETURNS integer LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE v_n integer := 0; v_c integer;
BEGIN
  IF NOT public.es_miembro_finca(p_finca) THEN
    RAISE EXCEPTION 'sin permiso para esta finca' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- 1. Ocupación mayor al límite aprobado (D-012)
  INSERT INTO public.alertas (finca_id, tipo, regla, mensaje, objeto_tipo, objeto_id, clave)
  SELECT p_finca, 'pastoreo', 'ocupacion_max_horas', v.mensaje, 'ocupaciones_pastoreo', v.ocupacion_id, 'ocupacion:' || v.ocupacion_id
    FROM public.v_alertas_ocupacion v WHERE v.finca_id = p_finca AND v.excede_limite
  ON CONFLICT (finca_id, clave) WHERE NOT is_deleted DO NOTHING;
  GET DIAGNOSTICS v_c = ROW_COUNT; v_n := v_n + v_c;
  -- 2. Aforos con puntos sin materia seca
  INSERT INTO public.alertas (finca_id, tipo, regla, mensaje, objeto_tipo, objeto_id, clave)
  SELECT p_finca, 'dato_pendiente', 'aforo_ms_pendiente',
         'Aforo del ' || to_char(r.fecha_aforo,'YYYY-MM-DD') || ': ' || (r.n_puntos - r.n_puntos_con_ms) || ' punto(s) sin materia seca',
         'aforos', r.aforo_id, 'aforo_ms:' || r.aforo_id
    FROM public.v_aforos_resumen r WHERE r.finca_id = p_finca AND r.n_puntos > r.n_puntos_con_ms
  ON CONFLICT (finca_id, clave) WHERE NOT is_deleted DO NOTHING;
  GET DIAGNOSTICS v_c = ROW_COUNT; v_n := v_n + v_c;
  -- 3. Observaciones sanitarias sin revisar
  INSERT INTO public.alertas (finca_id, tipo, regla, mensaje, objeto_tipo, objeto_id, clave)
  SELECT p_finca, 'sanidad', 'sanidad_sin_revision',
         'Observación sanitaria sin revisar: ' || left(e.descripcion, 80) || ' (no es diagnóstico)',
         'eventos_sanitarios', e.id, 'sanidad:' || e.id
    FROM public.eventos_sanitarios e WHERE e.finca_id = p_finca AND e.etapa = 'observacion' AND NOT e.is_deleted
  ON CONFLICT (finca_id, clave) WHERE NOT is_deleted DO NOTHING;
  GET DIAGNOSTICS v_c = ROW_COUNT; v_n := v_n + v_c;
  -- 4. Actividades vencidas
  INSERT INTO public.alertas (finca_id, tipo, regla, mensaje, objeto_tipo, objeto_id, clave)
  SELECT p_finca, 'operacion', 'actividad_vencida',
         'Actividad vencida: ' || a.titulo || ' (programada ' || to_char(a.fecha_programada AT TIME ZONE 'America/Bogota','YYYY-MM-DD HH24:MI') || ')',
         'actividades', a.id, 'actividad_vencida:' || a.id || ':' || a.version
    FROM public.actividades a
   WHERE a.finca_id = p_finca AND NOT a.is_deleted AND a.fecha_programada < now()
     AND a.estado IN ('programada','disponible','pendiente','reprogramada')
  ON CONFLICT (finca_id, clave) WHERE NOT is_deleted DO NOTHING;
  GET DIAGNOSTICS v_c = ROW_COUNT; v_n := v_n + v_c;
  -- 5. Operaciones QR en conflicto sin revisar (D-026)
  INSERT INTO public.alertas (finca_id, tipo, regla, mensaje, objeto_tipo, objeto_id, clave)
  SELECT p_finca, 'qr', 'qr_conflicto', 'Operación QR en conflicto (código ' || q.codigo || '): requiere revisión humana',
         'qr_operaciones', q.id, 'qr_conflicto:' || q.id
    FROM public.qr_operaciones q
   WHERE q.finca_id = p_finca AND q.estado = 'conflicto' AND q.revisado_en IS NULL AND NOT q.is_deleted
  ON CONFLICT (finca_id, clave) WHERE NOT is_deleted DO NOTHING;
  GET DIAGNOSTICS v_c = ROW_COUNT; v_n := v_n + v_c;
  -- 6. Calidad de datos: posibles inconsistencias o en revisión
  INSERT INTO public.alertas (finca_id, tipo, regla, mensaje, objeto_tipo, objeto_id, clave)
  SELECT p_finca, 'calidad', 'calidad_dato', 'Pesaje marcado "' || p.estado_calidad || '": ' || coalesce(p.nota_calidad,''),
         'pesajes', p.id, 'calidad:pesajes:' || p.id || ':' || p.estado_calidad
    FROM public.pesajes p WHERE p.finca_id = p_finca AND NOT p.is_deleted AND p.estado_calidad IN ('inconsistente','en_revision')
  ON CONFLICT (finca_id, clave) WHERE NOT is_deleted DO NOTHING;
  GET DIAGNOSTICS v_c = ROW_COUNT; v_n := v_n + v_c;
  INSERT INTO public.alertas (finca_id, tipo, regla, mensaje, objeto_tipo, objeto_id, clave)
  SELECT p_finca, 'calidad', 'calidad_dato', 'Aforo marcado "' || a.estado_calidad || '": ' || coalesce(a.nota_calidad,''),
         'aforos', a.id, 'calidad:aforos:' || a.id || ':' || a.estado_calidad
    FROM public.aforos a WHERE a.finca_id = p_finca AND NOT a.is_deleted AND a.estado_calidad IN ('inconsistente','en_revision')
  ON CONFLICT (finca_id, clave) WHERE NOT is_deleted DO NOTHING;
  GET DIAGNOSTICS v_c = ROW_COUNT; v_n := v_n + v_c;
  RETURN v_n;
END $$;

-- Convertir una alerta en actividad, decisión o hallazgo (la alerta queda trazada al destino)
CREATE OR REPLACE FUNCTION public.convertir_alerta(p_alerta uuid, p_destino text, p_titulo text, p_fecha timestamptz DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE a public.alertas; v_id uuid := gen_random_uuid();
BEGIN
  SELECT * INTO a FROM public.alertas WHERE id = p_alerta AND NOT is_deleted;
  IF a.id IS NULL OR NOT public.es_miembro_finca(a.finca_id) THEN
    RAISE EXCEPTION 'alerta no encontrada' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF a.estado NOT IN ('generada','pendiente','revisada','en_analisis') THEN
    RAISE EXCEPTION 'la alerta ya fue tratada (%)', a.estado USING ERRCODE = 'check_violation';
  END IF;
  IF btrim(coalesce(p_titulo,'')) = '' THEN p_titulo := a.mensaje; END IF;
  IF p_destino = 'actividad' THEN
    INSERT INTO public.actividades (id, finca_id, titulo, proceso, estado, origen_tipo, origen_id, objeto_tipo, objeto_id, fecha_programada)
    VALUES (v_id, a.finca_id, p_titulo, a.tipo, CASE WHEN p_fecha IS NULL THEN 'pendiente' ELSE 'programada' END,
            'alerta', a.id, a.objeto_tipo, a.objeto_id, p_fecha);
    UPDATE public.alertas SET estado = 'convertida_actividad', destino_tipo = 'actividades', destino_id = v_id WHERE id = a.id;
  ELSIF p_destino = 'decision' THEN
    INSERT INTO public.decisiones (id, finca_id, titulo, descripcion, datos_usados)
    VALUES (v_id, a.finca_id, p_titulo, 'Originada en la alerta: ' || a.mensaje, 'Alerta ' || a.regla || ' sobre ' || coalesce(a.objeto_tipo,'') );
    UPDATE public.alertas SET estado = 'convertida_decision', destino_tipo = 'decisiones', destino_id = v_id WHERE id = a.id;
  ELSIF p_destino = 'hallazgo' THEN
    INSERT INTO public.hallazgos (id, finca_id, tipo, titulo, descripcion, objeto_tipo, objeto_id, origen_tipo, origen_id, datos_usados)
    VALUES (v_id, a.finca_id, 'senal', p_titulo, a.mensaje, a.objeto_tipo, a.objeto_id, 'alerta', a.id,
            jsonb_build_object('regla', a.regla, 'alerta', a.id));
    UPDATE public.alertas SET estado = 'convertida_hallazgo', destino_tipo = 'hallazgos', destino_id = v_id WHERE id = a.id;
  ELSE
    RAISE EXCEPTION 'destino inválido (actividad, decision, hallazgo)' USING ERRCODE = 'check_violation';
  END IF;
  RETURN v_id;
END $$;

-- ---------------------------------------------------------------------------
-- 8. Vistas de lectura (siempre con los permisos de quien consulta)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_agenda WITH (security_invoker = true) AS
SELECT a.id, a.finca_id, 'actividad'::text AS clase, a.titulo, a.estado, a.proceso, a.origen_tipo,
       coalesce(a.fecha_programada, a.created_at) AS fecha, a.fecha_programada IS NULL AS sin_fecha,
       a.responsable, a.objeto_tipo, a.objeto_id,
       (a.fecha_programada < now() AND a.estado IN ('programada','disponible','pendiente','reprogramada')) AS vencida
  FROM public.actividades a
 WHERE NOT a.is_deleted AND a.estado NOT IN ('cerrada','cancelada','no_aplica','verificada')
UNION ALL
SELECT l.id, l.finca_id, 'alerta', l.mensaje, l.estado, l.tipo, l.regla, l.created_at, false, NULL, l.objeto_tipo, l.objeto_id, false
  FROM public.alertas l
 WHERE NOT l.is_deleted AND l.estado IN ('generada','pendiente','revisada','en_analisis');

CREATE OR REPLACE VIEW public.v_lluvia_diaria WITH (security_invoker = true) AS
SELECT finca_id, (fecha_hecho AT TIME ZONE 'America/Bogota')::date AS dia, naturaleza,
       sum(valor) AS mm, sum(valor) AS litros_por_m2,  -- 1 mm sobre 1 m² = 1 L (§25)
       count(*) AS registros
  FROM public.mediciones_ambientales
 WHERE variable = 'precipitacion' AND NOT is_deleted AND estado_calidad NOT IN ('rechazado','reemplazado','inconsistente')
 GROUP BY 1,2,3;

CREATE OR REPLACE VIEW public.v_descanso_unidades WITH (security_invoker = true) AS
SELECT o.finca_id, o.unidad_id, u.nombre AS unidad_nombre, o.id AS ocupacion_id, o.entrada_en,
       prev.salida_en AS salida_anterior,
       CASE WHEN prev.salida_en IS NULL THEN NULL
            ELSE round((extract(epoch FROM (o.entrada_en - prev.salida_en)) / 86400.0)::numeric, 1) END AS dias_descanso
  FROM public.ocupaciones_pastoreo o
  JOIN public.unidades_espaciales u ON u.id = o.unidad_id
  LEFT JOIN LATERAL (SELECT p.salida_en FROM public.ocupaciones_pastoreo p
                      WHERE p.unidad_id = o.unidad_id AND NOT p.is_deleted AND p.salida_en IS NOT NULL
                        AND p.salida_en <= o.entrada_en ORDER BY p.salida_en DESC LIMIT 1) prev ON true
 WHERE NOT o.is_deleted;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    EXECUTE 'GRANT SELECT ON public.v_agenda, public.v_lluvia_diaria, public.v_descanso_unidades TO authenticated';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON public.v_agenda, public.v_lluvia_diaria, public.v_descanso_unidades FROM anon';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 9. Tablero e informes (vistas sobre datos existentes; N/A ≠ 0)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.tablero_finca(p_finca uuid, p_desde date DEFAULT NULL, p_hasta date DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE
  v_desde timestamptz := coalesce(p_desde, (now() AT TIME ZONE 'America/Bogota')::date - 30)::timestamp AT TIME ZONE 'America/Bogota';
  v_hasta timestamptz := (coalesce(p_hasta, (now() AT TIME ZONE 'America/Bogota')::date) + 1)::timestamp AT TIME ZONE 'America/Bogota';
  r jsonb := '{}'::jsonb;
BEGIN
  IF NOT public.es_miembro_finca(p_finca) THEN
    RAISE EXCEPTION 'sin permiso para esta finca' USING ERRCODE = 'insufficient_privilege';
  END IF;
  PERFORM public.generar_alertas(p_finca);

  r := r || jsonb_build_object('periodo', jsonb_build_object('desde', v_desde, 'hasta', v_hasta, 'generado_en', now()));
  r := r || jsonb_build_object('finca', (SELECT jsonb_build_object('nombre', nombre, 'mision', mision, 'vision', vision,
                                                                   'datos_declarados_en', datos_declarados_en)
                                           FROM public.fincas WHERE id = p_finca));
  -- Ganadería
  r := r || jsonb_build_object('animales', jsonb_build_object(
    'total', (SELECT count(*) FROM public.animales WHERE finca_id = p_finca AND NOT is_deleted AND coalesce(estado,'activo') = 'activo'),
    'con_peso', (SELECT count(*) FROM public.animales WHERE finca_id = p_finca AND NOT is_deleted AND coalesce(estado,'activo') = 'activo' AND peso_ultimo IS NOT NULL),
    'peso_total_kg', (SELECT sum(peso_ultimo) FROM public.animales WHERE finca_id = p_finca AND NOT is_deleted AND coalesce(estado,'activo') = 'activo'),
    'por_categoria', coalesce((SELECT jsonb_agg(jsonb_build_object('etiqueta', coalesce(categoria,'sin categoría'), 'valor', n) ORDER BY n DESC)
                       FROM (SELECT categoria, count(*) n FROM public.animales WHERE finca_id = p_finca AND NOT is_deleted
                               AND coalesce(estado,'activo') = 'activo' GROUP BY categoria) x), '[]'::jsonb)));
  r := r || jsonb_build_object('lotes', (SELECT count(*) FROM public.lotes_ganaderos WHERE finca_id = p_finca AND NOT is_deleted));
  -- Territorio
  r := r || jsonb_build_object('territorio', jsonb_build_object(
    'potreros', (SELECT count(*) FROM public.unidades_espaciales WHERE finca_id = p_finca AND tipo = 'potrero' AND NOT is_deleted),
    'divisiones', (SELECT count(*) FROM public.unidades_espaciales WHERE finca_id = p_finca AND tipo = 'division' AND NOT is_deleted),
    'superficie_destinos', coalesce((SELECT jsonb_agg(jsonb_build_object('etiqueta', destino, 'valor', superficie_ha, 'naturaleza', naturaleza) ORDER BY superficie_ha DESC)
                               FROM public.destinos_superficie WHERE finca_id = p_finca AND NOT is_deleted), '[]'::jsonb),
    'fuentes_agua', (SELECT count(*) FROM public.fuentes_agua WHERE finca_id = p_finca AND NOT is_deleted),
    'fuentes_sin_ubicacion', (SELECT count(*) FROM public.fuentes_agua WHERE finca_id = p_finca AND NOT is_deleted AND latitud IS NULL),
    'muestras_suelo', (SELECT count(*) FROM public.muestras_suelo WHERE finca_id = p_finca AND NOT is_deleted)));
  -- Pastoreo
  r := r || jsonb_build_object('ocupaciones_activas', coalesce((SELECT jsonb_agg(jsonb_build_object(
      'unidad', unidad_nombre, 'lote', lote_nombre, 'horas', horas_ocupadas, 'limite', limite_horas, 'excede', excede_limite) ORDER BY horas_ocupadas DESC)
      FROM public.v_alertas_ocupacion WHERE finca_id = p_finca AND abierta), '[]'::jsonb));
  r := r || jsonb_build_object('aforos', coalesce((SELECT jsonb_agg(x ORDER BY (x->>'fecha') DESC) FROM (
      SELECT jsonb_build_object('fecha', a.fecha_aforo, 'unidad', u.nombre, 'ms_pct', a.ms_pct, 'agua_pct', a.agua_pct,
                                'ms_kg_ha', a.ms_kg_por_ha, 'estado', a.estado_ms_pct, 'puntos', a.n_puntos) x
        FROM public.v_aforos_resumen a LEFT JOIN public.unidades_espaciales u ON u.id = a.unidad_id
       WHERE a.finca_id = p_finca ORDER BY a.fecha_aforo DESC LIMIT 8) s), '[]'::jsonb));
  -- Alertas y operación
  r := r || jsonb_build_object('alertas', jsonb_build_object(
    'abiertas', (SELECT count(*) FROM public.alertas WHERE finca_id = p_finca AND NOT is_deleted AND estado IN ('generada','pendiente','revisada','en_analisis')),
    'por_tipo', coalesce((SELECT jsonb_agg(jsonb_build_object('etiqueta', tipo, 'valor', n)) FROM (
        SELECT tipo, count(*) n FROM public.alertas WHERE finca_id = p_finca AND NOT is_deleted
           AND estado IN ('generada','pendiente','revisada','en_analisis') GROUP BY tipo) x), '[]'::jsonb),
    'lista', coalesce((SELECT jsonb_agg(jsonb_build_object('id', id, 'tipo', tipo, 'mensaje', mensaje, 'estado', estado,
                       'objeto_tipo', objeto_tipo, 'objeto_id', objeto_id, 'creada', created_at) ORDER BY created_at DESC) FROM (
        SELECT * FROM public.alertas WHERE finca_id = p_finca AND NOT is_deleted
           AND estado IN ('generada','pendiente','revisada','en_analisis') ORDER BY created_at DESC LIMIT 12) x), '[]'::jsonb)));
  r := r || jsonb_build_object('actividades', jsonb_build_object(
    'por_estado', coalesce((SELECT jsonb_agg(jsonb_build_object('etiqueta', estado, 'valor', n)) FROM (
        SELECT estado, count(*) n FROM public.actividades WHERE finca_id = p_finca AND NOT is_deleted GROUP BY estado) x), '[]'::jsonb),
    'vencidas', (SELECT count(*) FROM public.v_agenda WHERE finca_id = p_finca AND vencida),
    'por_verificar', (SELECT count(*) FROM public.actividades WHERE finca_id = p_finca AND NOT is_deleted AND estado = 'requiere_verificacion'),
    'proximas', coalesce((SELECT jsonb_agg(jsonb_build_object('id', id, 'titulo', titulo, 'estado', estado, 'fecha', fecha,
                          'sin_fecha', sin_fecha, 'vencida', vencida) ORDER BY vencida DESC, sin_fecha, fecha) FROM (
        SELECT * FROM public.v_agenda WHERE finca_id = p_finca AND clase = 'actividad'
         ORDER BY vencida DESC, sin_fecha, fecha LIMIT 10) x), '[]'::jsonb)));
  -- Flujo dato → mejora (§8): conteos por etapa
  r := r || jsonb_build_object('flujo', jsonb_build_array(
    jsonb_build_object('etapa','Datos','valor',
      (SELECT count(*) FROM public.pesajes WHERE finca_id = p_finca AND NOT is_deleted)
    + (SELECT count(*) FROM public.aforos WHERE finca_id = p_finca AND NOT is_deleted)
    + (SELECT count(*) FROM public.mediciones_ambientales WHERE finca_id = p_finca AND NOT is_deleted)
    + (SELECT count(*) FROM public.eventos_sanitarios WHERE finca_id = p_finca AND NOT is_deleted)
    + (SELECT count(*) FROM public.eventos_reproductivos WHERE finca_id = p_finca AND NOT is_deleted)
    + (SELECT count(*) FROM public.produccion_leche WHERE finca_id = p_finca AND NOT is_deleted)
    + (SELECT count(*) FROM public.observaciones WHERE finca_id = p_finca AND NOT is_deleted), 'ruta','/monitoreo'),
    jsonb_build_object('etapa','Cálculos','valor',(SELECT count(*) FROM public.calculos WHERE finca_id = p_finca AND NOT is_deleted),'ruta','/monitoreo'),
    jsonb_build_object('etapa','Alertas/señales','valor',(SELECT count(*) FROM public.alertas WHERE finca_id = p_finca AND NOT is_deleted),'ruta','/e/alertas'),
    jsonb_build_object('etapa','Hallazgos','valor',(SELECT count(*) FROM public.hallazgos WHERE finca_id = p_finca AND NOT is_deleted),'ruta','/e/hallazgos'),
    jsonb_build_object('etapa','Recomendaciones','valor',(SELECT count(*) FROM public.recomendaciones WHERE finca_id = p_finca AND NOT is_deleted),'ruta','/e/recomendaciones'),
    jsonb_build_object('etapa','Decisiones','valor',(SELECT count(*) FROM public.decisiones WHERE finca_id = p_finca AND NOT is_deleted),'ruta','/e/decisiones'),
    jsonb_build_object('etapa','Actividades','valor',(SELECT count(*) FROM public.actividades WHERE finca_id = p_finca AND NOT is_deleted),'ruta','/e/actividades'),
    jsonb_build_object('etapa','Verificadas','valor',(SELECT count(*) FROM public.actividades WHERE finca_id = p_finca AND NOT is_deleted AND estado IN ('verificada','cerrada')),'ruta','/e/actividades'),
    jsonb_build_object('etapa','Aprendizajes','valor',(SELECT count(*) FROM public.aprendizajes WHERE finca_id = p_finca AND NOT is_deleted),'ruta','/e/aprendizajes')));
  r := r || jsonb_build_object('decisiones_por_estado', coalesce((SELECT jsonb_agg(jsonb_build_object('etiqueta', estado, 'valor', n)) FROM (
        SELECT estado, count(*) n FROM public.decisiones WHERE finca_id = p_finca AND NOT is_deleted GROUP BY estado) x), '[]'::jsonb));
  -- Series del periodo (informes)
  r := r || jsonb_build_object('lluvia', jsonb_build_object(
    'total_mm', (SELECT sum(valor) FROM public.mediciones_ambientales WHERE finca_id = p_finca AND variable = 'precipitacion' AND NOT is_deleted
                   AND estado_calidad NOT IN ('rechazado','reemplazado','inconsistente') AND fecha_hecho >= v_desde AND fecha_hecho < v_hasta),
    'registros', (SELECT count(*) FROM public.mediciones_ambientales WHERE finca_id = p_finca AND variable = 'precipitacion' AND NOT is_deleted
                   AND fecha_hecho >= v_desde AND fecha_hecho < v_hasta),
    'serie', coalesce((SELECT jsonb_agg(jsonb_build_object('etiqueta', to_char(dia,'MM-DD'), 'valor', mm) ORDER BY dia) FROM (
        SELECT dia, sum(mm) mm FROM public.v_lluvia_diaria WHERE finca_id = p_finca AND dia >= v_desde::date AND dia < v_hasta::date GROUP BY dia) x), '[]'::jsonb)));
  r := r || jsonb_build_object('leche', jsonb_build_object(
    'total_litros', (SELECT sum(litros) FROM public.produccion_leche WHERE finca_id = p_finca AND NOT is_deleted
                       AND estado_calidad NOT IN ('rechazado','reemplazado','inconsistente') AND fecha_hecho >= v_desde AND fecha_hecho < v_hasta),
    'entregado_litros', (SELECT sum(litros) FROM public.entregas_leche WHERE finca_id = p_finca AND NOT is_deleted AND estado <> 'rechazada'
                       AND fecha_hecho >= v_desde AND fecha_hecho < v_hasta),
    'pagado_cop', (SELECT sum(valor_cop) FROM public.entregas_leche WHERE finca_id = p_finca AND NOT is_deleted AND estado = 'pagada'
                       AND fecha_hecho >= v_desde AND fecha_hecho < v_hasta),
    'serie', coalesce((SELECT jsonb_agg(jsonb_build_object('etiqueta', to_char(dia,'MM-DD'), 'valor', l) ORDER BY dia) FROM (
        SELECT (fecha_hecho AT TIME ZONE 'America/Bogota')::date dia, sum(litros) l FROM public.produccion_leche
         WHERE finca_id = p_finca AND NOT is_deleted AND fecha_hecho >= v_desde AND fecha_hecho < v_hasta GROUP BY 1) x), '[]'::jsonb)));
  r := r || jsonb_build_object('economia', coalesce((SELECT jsonb_agg(jsonb_build_object('etiqueta', clase, 'valor', v)) FROM (
        SELECT clase, sum(valor_cop) v FROM public.movimientos_economicos WHERE finca_id = p_finca AND NOT is_deleted
           AND fecha_hecho >= v_desde AND fecha_hecho < v_hasta GROUP BY clase) x), '[]'::jsonb));
  r := r || jsonb_build_object('pesajes_periodo', (SELECT count(*) FROM public.pesajes WHERE finca_id = p_finca AND NOT is_deleted
                                                     AND fecha_pesaje >= v_desde AND fecha_pesaje < v_hasta));
  r := r || jsonb_build_object('sanidad_abiertos', (SELECT count(*) FROM public.eventos_sanitarios WHERE finca_id = p_finca AND NOT is_deleted
                                                     AND etapa NOT IN ('verificacion','cerrado')));
  r := r || jsonb_build_object('infraestructura_por_estado', coalesce((SELECT jsonb_agg(jsonb_build_object('etiqueta', estado, 'valor', n)) FROM (
        SELECT estado, count(*) n FROM public.infraestructuras WHERE finca_id = p_finca AND NOT is_deleted GROUP BY estado) x), '[]'::jsonb));
  r := r || jsonb_build_object('sistemas', coalesce((SELECT jsonb_agg(jsonb_build_object('nombre', nombre, 'tipo', tipo, 'estado', estado,
                                 'superficie_ha', superficie_ha, 'naturaleza', superficie_naturaleza) ORDER BY tipo)
                               FROM public.sistemas_productivos WHERE finca_id = p_finca AND NOT is_deleted), '[]'::jsonb));
  r := r || jsonb_build_object('guias', jsonb_build_object(
    'total', (SELECT count(*) FROM public.guias WHERE finca_id = p_finca AND NOT is_deleted),
    'publicadas', (SELECT count(DISTINCT guia_id) FROM public.guia_versiones WHERE finca_id = p_finca AND NOT is_deleted AND estado = 'publicada')));
  r := r || jsonb_build_object('incidentes_abiertos', (SELECT count(*) FROM public.incidentes_tecnicos WHERE finca_id = p_finca AND NOT is_deleted
                                                        AND estado NOT IN ('cerrado','verificado','resuelto')));
  RETURN r;
END $$;

-- Búsqueda sobre la información existente (nunca inventa resultados)
CREATE OR REPLACE FUNCTION public.buscar_finca(p_finca uuid, p_texto text)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path = public, pg_temp AS $$
DECLARE q text := '%' || lower(btrim(coalesce(p_texto,''))) || '%';
BEGIN
  IF NOT public.es_miembro_finca(p_finca) THEN
    RAISE EXCEPTION 'sin permiso para esta finca' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF length(btrim(coalesce(p_texto,''))) < 1 THEN RETURN '[]'::jsonb; END IF;
  RETURN coalesce((SELECT jsonb_agg(x) FROM (
    SELECT jsonb_build_object('tabla','animales','id',id,'titulo','Animal ' || numero_interno,'detalle',coalesce(categoria,'')) x
      FROM public.animales WHERE finca_id = p_finca AND NOT is_deleted AND (lower(numero_interno) LIKE q OR lower(coalesce(categoria,'')) LIKE q)
    UNION ALL SELECT jsonb_build_object('tabla','lotes_ganaderos','id',id,'titulo','Lote ' || nombre,'detalle',coalesce(estado,''))
      FROM public.lotes_ganaderos WHERE finca_id = p_finca AND NOT is_deleted AND lower(nombre) LIKE q
    UNION ALL SELECT jsonb_build_object('tabla','unidades_espaciales','id',id,'titulo',coalesce(tipo,'unidad') || ' ' || coalesce(nombre,''),'detalle',coalesce(estado,''))
      FROM public.unidades_espaciales WHERE finca_id = p_finca AND NOT is_deleted AND lower(coalesce(nombre,'')) LIKE q
    UNION ALL SELECT jsonb_build_object('tabla','infraestructuras','id',id,'titulo',nombre,'detalle',tipo || ' · ' || estado)
      FROM public.infraestructuras WHERE finca_id = p_finca AND NOT is_deleted AND (lower(nombre) LIKE q OR lower(tipo) LIKE q)
    UNION ALL SELECT jsonb_build_object('tabla','recursos','id',id,'titulo',nombre,'detalle',clase || ' · ' || estado)
      FROM public.recursos WHERE finca_id = p_finca AND NOT is_deleted AND lower(nombre) LIKE q
    UNION ALL SELECT jsonb_build_object('tabla','fuentes_agua','id',id,'titulo',nombre,'detalle',tipo)
      FROM public.fuentes_agua WHERE finca_id = p_finca AND NOT is_deleted AND lower(nombre) LIKE q
    UNION ALL SELECT jsonb_build_object('tabla','sistemas_productivos','id',id,'titulo',nombre,'detalle',tipo)
      FROM public.sistemas_productivos WHERE finca_id = p_finca AND NOT is_deleted AND lower(nombre) LIKE q
    UNION ALL SELECT jsonb_build_object('tabla','especies','id',id,'titulo',nombre_comun,'detalle',coalesce(nombre_cientifico,''))
      FROM public.especies WHERE finca_id = p_finca AND NOT is_deleted AND (lower(nombre_comun) LIKE q OR lower(coalesce(nombre_cientifico,'')) LIKE q)
    UNION ALL SELECT jsonb_build_object('tabla','actividades','id',id,'titulo',titulo,'detalle',estado)
      FROM public.actividades WHERE finca_id = p_finca AND NOT is_deleted AND lower(titulo) LIKE q
    UNION ALL SELECT jsonb_build_object('tabla','decisiones','id',id,'titulo',titulo,'detalle',estado)
      FROM public.decisiones WHERE finca_id = p_finca AND NOT is_deleted AND lower(titulo) LIKE q
    UNION ALL SELECT jsonb_build_object('tabla','recomendaciones','id',id,'titulo',titulo,'detalle',estado)
      FROM public.recomendaciones WHERE finca_id = p_finca AND NOT is_deleted AND lower(titulo) LIKE q
    UNION ALL SELECT jsonb_build_object('tabla','hallazgos','id',id,'titulo',titulo,'detalle',tipo || ' · ' || estado)
      FROM public.hallazgos WHERE finca_id = p_finca AND NOT is_deleted AND lower(titulo) LIKE q
    UNION ALL SELECT jsonb_build_object('tabla','aprendizajes','id',id,'titulo',titulo,'detalle',estado)
      FROM public.aprendizajes WHERE finca_id = p_finca AND NOT is_deleted AND lower(titulo) LIKE q
    UNION ALL SELECT jsonb_build_object('tabla','guias','id',id,'titulo','Guía: ' || titulo,'detalle',codigo)
      FROM public.guias WHERE finca_id = p_finca AND NOT is_deleted AND (lower(titulo) LIKE q OR lower(codigo) LIKE q)
    UNION ALL SELECT jsonb_build_object('tabla','eventos_sanitarios','id',id,'titulo','Sanidad: ' || left(descripcion,60),'detalle',tipo || ' · ' || etapa)
      FROM public.eventos_sanitarios WHERE finca_id = p_finca AND NOT is_deleted AND lower(descripcion) LIKE q
    LIMIT 60) s), '[]'::jsonb);
END $$;

-- ---------------------------------------------------------------------------
-- 10. Datos declarados por el usuario en la arquitectura (Prompt §17, §22, §23; V5 §2.2)
--     Se cargan SOLO si el usuario lo pide desde la app. Nada se inventa: lo aproximado
--     queda "estimado", lo obtenido por resta "calculado", lo proyectado "proyectado".
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cargar_datos_declarados(p_finca uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_p1 uuid; v_n int := 0;
BEGIN
  IF NOT public.es_miembro_finca(p_finca) THEN
    RAISE EXCEPTION 'sin permiso para esta finca' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF (SELECT datos_declarados_en FROM public.fincas WHERE id = p_finca) IS NOT NULL THEN
    RETURN jsonb_build_object('resultado','ya_cargados');
  END IF;
  -- Infraestructura (§22)
  INSERT INTO public.infraestructuras (finca_id, tipo, nombre, estado, descripcion, naturaleza) VALUES
    (p_finca,'vivienda','Vivienda principal','existente',NULL,'observado'),
    (p_finca,'cerca','Cercas de alambre','existente','Parciales (no cubren toda la finca). Longitud: sin datos.','observado'),
    (p_finca,'corral_embarque','Estructura / corral de embarque','pendiente_verificacion','Declarada en mal estado.','observado'),
    (p_finca,'corral','Corral','proyectado','Actualmente no existe corral; existe el proyecto.','observado');
  INSERT INTO public.recursos (finca_id, clase, nombre, cantidad, estado, descripcion, naturaleza) VALUES
    (p_finca,'material','Láminas de zinc',NULL,'disponible','Cantidad: sin datos.','observado');
  -- Agua (§23): nacimientos identificados, sin ubicación todavía
  INSERT INTO public.fuentes_agua (finca_id, tipo, nombre, estado, conservacion, descripcion, naturaleza) VALUES
    (p_finca,'nacimiento','Nacimientos identificados','pendiente_verificacion',true,
     'Declarados en la arquitectura. Cantidad y georreferenciación: pendientes. No existe red de mangueras ni tanques.','observado');
  -- Superficies declaradas (V5 §2.2)
  INSERT INTO public.destinos_superficie (finca_id, destino, superficie_ha, naturaleza, observaciones) VALUES
    (p_finca,'Superficie total',33,'estimado','Declarada por el usuario'),
    (p_finca,'Pancoger',4,'estimado','Declarada por el usuario'),
    (p_finca,'Banco de forraje mixto (proyectado)',4,'estimado','A futuro, para ensilaje'),
    (p_finca,'Bosque (conservación)',4,'estimado','Aproximado; sin afirmar protección legal'),
    (p_finca,'Humedal (conservación)',1,'estimado','Aproximado, forma alargada; la geometría real definirá el área'),
    (p_finca,'Ganadería',20,'calculado','33 − 13 (por resta); aproximado porque bosque y humedal son aproximados')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.sistemas_productivos (finca_id, tipo, nombre, superficie_ha, superficie_naturaleza, estado, descripcion) VALUES
    (p_finca,'ganaderia','Ganadería (Girolando)',20,'calculado','activo','Máx. 6 potreros principales, ocupación máx. 2 días'),
    (p_finca,'pancoger','Pancoger',4,'estimado','activo',NULL),
    (p_finca,'banco_forraje','Banco de forraje mixto para ensilaje',4,'estimado','proyectado',NULL),
    (p_finca,'conservacion','Bosque',4,'estimado','activo','Sin afirmar protección legal'),
    (p_finca,'conservacion','Humedal',1,'estimado','activo','Sin afirmar protección legal'),
    (p_finca,'vivero','Vivero',NULL,NULL,'proyectado','Superficie: sin datos');
  -- Pastoreo (§17): Potrero 1 con divisiones temporales A1, A2, A3
  SELECT id INTO v_p1 FROM public.unidades_espaciales
   WHERE finca_id = p_finca AND tipo = 'potrero' AND lower(btrim(nombre)) = 'potrero 1' AND NOT is_deleted LIMIT 1;
  IF v_p1 IS NULL AND (SELECT count(*) FROM public.unidades_espaciales
                        WHERE finca_id = p_finca AND tipo = 'potrero' AND NOT is_deleted) < 6
     AND NOT EXISTS (SELECT 1 FROM public.unidades_espaciales WHERE finca_id = p_finca AND NOT is_deleted
                      AND tipo IN ('potrero','division') AND lower(btrim(nombre)) = 'potrero 1') THEN
    INSERT INTO public.unidades_espaciales (finca_id, tipo, nombre, es_temporal, estado)
    VALUES (p_finca, 'potrero', 'Potrero 1', false, 'disponible') RETURNING id INTO v_p1;
  END IF;
  IF v_p1 IS NOT NULL THEN
    INSERT INTO public.unidades_espaciales (finca_id, parent_id, tipo, nombre, es_temporal, estado)
    SELECT p_finca, v_p1, 'division', d, true, 'disponible' FROM unnest(ARRAY['A1','A2','A3']) d
     WHERE NOT EXISTS (SELECT 1 FROM public.unidades_espaciales u WHERE u.finca_id = p_finca AND NOT u.is_deleted
                        AND u.tipo IN ('potrero','division') AND lower(btrim(u.nombre)) = lower(d));
  END IF;
  UPDATE public.fincas SET datos_declarados_en = now() WHERE id = p_finca;
  RETURN jsonb_build_object('resultado','cargados');
END $$;

-- ---------------------------------------------------------------------------
-- 11. Guías base: estructura de la regla de oro con el contenido QUE YA DEFINE la arquitectura.
--     Quedan en BORRADOR (publicar exige los 22 elementos, fuente y revisor). Lo no definido
--     queda vacío = "pendiente de contenido validado" (34.16).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.crear_guias_base(p_finca uuid)
RETURNS integer LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE v_n int := 0; g record; v_id uuid;
BEGIN
  IF NOT public.es_miembro_finca(p_finca) THEN
    RAISE EXCEPTION 'sin permiso para esta finca' USING ERRCODE = 'insufficient_privilege';
  END IF;
  FOR g IN SELECT * FROM (VALUES
    ('muestreo_suelo','Toma de muestra de suelo',
     'Muestra compuesta de suelo para análisis de laboratorio.',
     'Conocer las características químicas y físicas del suelo de una unidad.',
     'Un resultado de laboratorio NO produce automáticamente una recomendación de fertilización.',
     'En la unidad espacial a caracterizar, evitando puntos contaminados.',
     NULL,
     'Recipiente plástico limpio, bolsa nueva, marcador permanente, etiqueta.',
     'cm (profundidad), kg (muestra), número de puntos',
     E'1. Limpiar superficialmente sin raspar ni remover suelo relevante.\n2. Hacer un hueco en V de aproximadamente 20 cm cuando corresponda al método.\n3. Trabajar con humedad adecuada.\n4. Obtener una lámina de aproximadamente 3 cm y conservar la parte central.\n5. Repetir en aproximadamente 15–20 puntos.\n6. Mezclar en recipiente plástico limpio.\n7. Obtener aproximadamente 1 kg.\n8. Empacar en bolsa nueva, marcar con marcador permanente y etiquetar.',
     'Evitar puntos contaminados.',
     NULL,
     'No muestrear debajo de cercas, zonas minerales o salinas, bebederos, zonas de descanso, junto a árboles aislados ni en quemas recientes.',
     'Registrar la muestra (etiqueta, unidad, fecha, número de puntos, profundidad) y luego los resultados: pH en agua, fósforo Bray II, saturación de aluminio, aluminio, materia orgánica, calcio, magnesio, potasio, textura.',
     'Prompt Maestro §24 (procedimiento conceptual definido en la arquitectura)'),
    ('aforo_materia_seca','Aforo y materia seca del forraje',
     'Muestreo del forraje cortando el área de muestra en varios puntos del potrero o división.',
     'Saber cuánta materia seca y cuánta agua tiene el pasto.',
     'La oferta de forraje se relaciona con la demanda del lote (oferta − demanda no equivale a consumo real).',
     'En varios puntos del potrero o división.',
     '%MS = masa seca ÷ masa fresca × 100; %agua = 100 − %MS.',
     NULL,
     'g (masa fresca y seca), m² (área por punto), %',
     E'1. Elegir varios puntos del área.\n2. Medir el área de cada punto (no se asume 1 m²).\n3. Cortar y pesar la masa fresca al cortar.\n4. Secar y pesar la masa seca (puede quedar pendiente).\n5. Registrar cada punto.',
     NULL, NULL, NULL,
     'Potrero/división, fecha, hora, método, puntos, masa fresca, masa seca, superficie, condiciones, evidencia, usuario, validación.',
     'Prompt Maestro §18 y CHG-014 (fórmula cerrada)'),
    ('lluvia','Registro de lluvia',
     'Registro de precipitación en milímetros.',
     'Conocer el agua que cae sobre la finca.',
     '1 mm de lluvia sobre 1 m² = 1 litro. El volumen potencial no equivale a escorrentía, captación ni agua utilizable.',
     NULL, NULL, NULL, 'mm; L/m²', NULL, NULL, NULL, NULL,
     'Distinguir medición local, fuente externa, histórico, modelado y pronóstico (naturaleza del dato).',
     'Prompt Maestro §25'),
    ('pesaje_bovino','Pesaje de bovinos',
     'Registro del peso vivo de un animal.',
     'El peso alimenta la demanda de materia seca, el pastoreo y los indicadores.',
     NULL, NULL, NULL, NULL, 'kg', NULL, NULL, NULL, NULL,
     'Valor, unidad, método, fecha, responsable y naturaleza (medido o estimado: una estimación no es una medición).',
     'Documento Maestro V4 §6.1'),
    ('ocupacion_pastoreo','Entrada y salida de pastoreo',
     'Registro de cuándo un lote entra y sale de un potrero o división.',
     'Controlar la ocupación (máximo aprobado 2 días) y calcular el descanso.',
     'Superar el límite genera alerta sin inferir la causa. Planificado ≠ ejecutado.',
     'Potreros principales (máx. 6) y sus divisiones temporales.',
     'Descanso = nuevo ingreso − salida anterior de la misma unidad.',
     NULL, 'horas, días', NULL, NULL, NULL, NULL,
     'Lote, unidad, fecha y hora de entrada y de salida.',
     'Prompt Maestro §17, D-012'),
    ('observacion_sanitaria','Observación sanitaria',
     'Registro de lo que se observa en la salud de un animal o lote.',
     'Iniciar el flujo: observación → revisión → diagnóstico profesional → tratamiento autorizado → seguimiento → verificación.',
     'Observación ≠ diagnóstico. El diagnóstico y el tratamiento los define un profesional.',
     NULL, NULL, NULL, NULL, NULL, NULL, NULL,
     'No presentar una observación como diagnóstico.',
     'Animal o lote, fecha, descripción de lo observado, evidencia (foto).',
     'Prompt Maestro §20'),
    ('fotografia_animal','Fotografía estandarizada del animal',
     'Serie de fotografías: principal, cuerpo, identificación, específicas y ubre cuando corresponda.',
     'Identificar al animal y documentar su condición.',
     '"360°" significa una secuencia de fotos desde diferentes ángulos, no un archivo 360° ni un modelo 3D.',
     NULL, NULL, NULL, NULL, NULL, NULL, NULL,
     'La foto de ubre es evidencia visual, no diagnóstico automático.',
     'Tipo de foto, animal, fecha; el archivo va a Google Drive.',
     'Prompt Maestro §16'),
    ('georreferenciacion','Georreferenciación de puntos y polígonos',
     'Registro de ubicación de nacimientos, infraestructura y unidades.',
     'Ubicar en el mapa la información existente.',
     'La cartografía operativa (GPS de recorrido) no equivale a levantamiento legal, topográfico ni geodésico.',
     NULL, NULL, NULL, 'grados decimales, metros (precisión)', NULL, NULL, NULL, NULL,
     'Latitud, longitud, precisión, método, fecha, hora, usuario, tipo, evidencia.',
     'Prompt Maestro §45'),
    ('demanda_ms','Demanda de materia seca del lote',
     'Cálculo de la materia seca que requiere un lote por día.',
     'Comparar con la oferta de forraje para planificar el pastoreo.',
     'Oferta − demanda no equivale a consumo real.',
     NULL,
     'Demanda = peso vivo total × % de consumo de MS (referencia configurable 2–3 %, no universal). Si falta un peso o el criterio: NO CALCULABLE.',
     NULL, 'kg MS/día', NULL, NULL, NULL, NULL,
     'Se guarda el cálculo con las entradas, su naturaleza, el criterio y su versión.',
     'Prompt Maestro §18, 00009')
  ) AS t(codigo, titulo, que_es, para_que, por_que, donde, metodo, materiales, unidades, pasos, precauciones, errores, prohibiciones, registro, fuente)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM public.guias WHERE finca_id = p_finca AND lower(codigo) = g.codigo AND NOT is_deleted) THEN
      INSERT INTO public.guias (finca_id, codigo, titulo) VALUES (p_finca, g.codigo, g.titulo) RETURNING id INTO v_id;
      INSERT INTO public.guia_versiones (finca_id, guia_id, numero, estado, que_es, para_que, por_que, donde, metodo,
                                         materiales, unidades, pasos, precauciones, errores_comunes, prohibiciones, registro, fuente)
      VALUES (p_finca, v_id, 1, 'borrador', g.que_es, g.para_que, g.por_que, g.donde, g.metodo,
              g.materiales, g.unidades, g.pasos, g.precauciones, g.errores, g.prohibiciones, g.registro, g.fuente);
      v_n := v_n + 1;
    END IF;
  END LOOP;
  RETURN v_n;
END $$;

-- ---------------------------------------------------------------------------
-- 12. Permisos de funciones: nadie anónimo; triggers no invocables por API
-- ---------------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT p.oid::regprocedure AS fn, pg_get_function_result(p.oid) AS res
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND p.prokind = 'f'
              AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', r.fn);
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', r.fn);
    END IF;
    IF r.res = 'trigger' AND EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM authenticated', r.fn);
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    EXECUTE 'REVOKE EXECUTE ON FUNCTION public.tarea_auto(uuid,text,text,text,text,uuid,text,uuid,timestamptz,text,uuid,uuid,uuid) FROM authenticated';
    EXECUTE 'REVOKE EXECUTE ON FUNCTION public.tarea_auto_ejecutada(uuid,text,text) FROM authenticated';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.tablero_finca(uuid,date,date) TO authenticated';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.generar_alertas(uuid) TO authenticated';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.convertir_alerta(uuid,text,text,timestamptz) TO authenticated';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.buscar_finca(uuid,text) TO authenticated';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.cargar_datos_declarados(uuid) TO authenticated';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.crear_guias_base(uuid) TO authenticated';
    -- los triggers que llaman a estas funciones corren como el usuario: necesitan EXECUTE interno
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.tarea_auto(uuid,text,text,text,text,uuid,text,uuid,timestamptz,text,uuid,uuid,uuid) TO authenticated';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.tarea_auto_ejecutada(uuid,text,text) TO authenticated';
  END IF;
END $$;
