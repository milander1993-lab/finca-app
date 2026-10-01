-- ============================================================================
-- 00009_motor_calculo_demanda_ms.sql — Motor de cálculo DETERMINÍSTICO (D-016)
-- ADITIVA e idempotente. Requiere 00002–00008.
--
-- Protocolo de cálculos (prompt §86): entradas, unidades, fórmula, método, criterio,
-- periodo, alcance, versión, entradas indispensables, comportamiento ante faltantes,
-- evidencia y auditoría. La IA NO calcula.
--
-- Fórmula implementada (versión 'demanda_ms_lote.v1'):
--   demanda_ms_kg_dia = SUM(peso_vivo_kg de cada animal del lote a la fecha) × pct / 100
--   pct = criterio 'ms_pct_peso_vivo' vigente a esa fecha (configurable por finca).
-- NO se siembra ningún valor: sin criterio vigente o sin peso de algún animal el
-- resultado es NO_CALCULABLE (nunca 0, nunca parcial).
-- ============================================================================
DO $$ BEGIN
  IF to_regclass('public.aforos') IS NULL OR to_regclass('public.animal_lote') IS NULL
     OR to_regclass('public.pesajes') IS NULL THEN
    RAISE EXCEPTION '00009 requiere 00002 a 00008.';
  END IF;
END $$;

-- Criterios/parámetros versionados (append-only: cambiar = nueva fila con vigente_desde)
CREATE TABLE IF NOT EXISTS public.criterios_parametros (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id      uuid NOT NULL REFERENCES public.fincas(id),
  codigo        text NOT NULL CHECK (btrim(codigo) <> ''),
  nombre        text NOT NULL CHECK (btrim(nombre) <> ''),
  valor         numeric NOT NULL CHECK (valor > 0),
  unidad        text NOT NULL CHECK (btrim(unidad) <> ''),
  vigente_desde timestamptz NOT NULL DEFAULT now(),
  fuente        text NOT NULL CHECK (btrim(fuente) <> ''),     -- de dónde sale (requisito §53)
  limitaciones  text,
  validador_id  uuid REFERENCES auth.users(id),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  created_by    uuid REFERENCES auth.users(id),
  updated_by    uuid REFERENCES auth.users(id),
  version       integer NOT NULL DEFAULT 1,
  is_deleted    boolean NOT NULL DEFAULT false,
  CHECK (codigo <> 'ms_pct_peso_vivo' OR (valor > 0 AND valor <= 100 AND unidad = '% peso vivo/día'))
);
CREATE INDEX IF NOT EXISTS ix_criterios_vigencia
  ON public.criterios_parametros (finca_id, codigo, vigente_desde DESC) WHERE NOT is_deleted;

-- Resultados de cálculo: conservan datos usados, método, fórmula, versión, fecha, usuario (§ decisiones)
CREATE TABLE IF NOT EXISTS public.calculos (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id         uuid NOT NULL REFERENCES public.fincas(id),
  codigo_calculo   text NOT NULL,                  -- p. ej. demanda_ms_lote
  version_formula  text NOT NULL,                  -- p. ej. demanda_ms_lote.v1
  formula          text NOT NULL,                  -- texto de la fórmula aplicada
  alcance_tipo     text NOT NULL,                  -- 'lote'
  alcance_id       uuid NOT NULL,
  periodo_fecha    timestamptz NOT NULL,           -- fecha a la que se calcula
  resultado        text NOT NULL CHECK (resultado IN ('calculado','no_calculable')),
  valor            numeric,
  unidad           text,
  naturaleza       public.naturaleza_dato NOT NULL DEFAULT 'calculado',
  parametro_id     uuid REFERENCES public.criterios_parametros(id),
  entradas         jsonb NOT NULL,                 -- datos usados (con su naturaleza y fecha)
  faltantes        jsonb,                          -- por qué no es calculable
  incertidumbre    text,                           -- p. ej. pesos estimados
  calculado_por    uuid REFERENCES auth.users(id),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  created_by       uuid REFERENCES auth.users(id),
  updated_by       uuid REFERENCES auth.users(id),
  version          integer NOT NULL DEFAULT 1,
  is_deleted       boolean NOT NULL DEFAULT false,
  CHECK ((resultado = 'calculado' AND valor IS NOT NULL AND unidad IS NOT NULL AND faltantes IS NULL)
      OR (resultado = 'no_calculable' AND valor IS NULL AND faltantes IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS ix_calculos_alcance
  ON public.calculos (finca_id, alcance_tipo, alcance_id, created_at DESC) WHERE NOT is_deleted;

-- Append-only: ni criterios ni resultados se reescriben (solo se anulan con is_deleted)
CREATE OR REPLACE FUNCTION public.solo_anular()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF (to_jsonb(NEW) - ARRAY['is_deleted','updated_at','updated_by','version'])
     IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['is_deleted','updated_at','updated_by','version']) THEN
    RAISE EXCEPTION 'registro de solo-anular: un cambio se registra como una fila nueva (D-010)'
      USING ERRCODE = 'restrict_violation';
  END IF;
  RETURN NEW;
END $$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['criterios_parametros','calculos'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS t10_sellar_autoria ON public.%I', t);
    EXECUTE format('CREATE TRIGGER t10_sellar_autoria BEFORE INSERT OR UPDATE ON public.%I
                    FOR EACH ROW EXECUTE FUNCTION public.sellar_autoria()', t);
    IF NOT EXISTS (SELECT 1 FROM pg_trigger g WHERE g.tgrelid = format('public.%I', t)::regclass
                   AND NOT g.tgisinternal AND g.tgfoid = 'public.actualizar_timestamps()'::regprocedure) THEN
      EXECUTE format('CREATE TRIGGER t20_timestamps BEFORE UPDATE ON public.%I
                      FOR EACH ROW EXECUTE FUNCTION public.actualizar_timestamps()', t);
    END IF;
    EXECUTE format('DROP TRIGGER IF EXISTS t30_bloquear_delete ON public.%I', t);
    EXECUTE format('CREATE TRIGGER t30_bloquear_delete BEFORE DELETE ON public.%I
                    FOR EACH ROW EXECUTE FUNCTION public.bloquear_delete()', t);
    EXECUTE format('DROP TRIGGER IF EXISTS t50_solo_anular ON public.%I', t);
    EXECUTE format('CREATE TRIGGER t50_solo_anular BEFORE UPDATE ON public.%I
                    FOR EACH ROW EXECUTE FUNCTION public.solo_anular()', t);
    EXECUTE format('DROP TRIGGER IF EXISTS t90_auditar ON public.%I', t);
    EXECUTE format('CREATE TRIGGER t90_auditar AFTER INSERT OR UPDATE ON public.%I
                    FOR EACH ROW EXECUTE FUNCTION public.auditar_cambio()', t);
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
  END LOOP;
END $$;

-- Cálculo: demanda de materia seca de un lote a una fecha ---------------------------
CREATE OR REPLACE FUNCTION public.calcular_demanda_ms_lote(
  p_finca uuid, p_lote uuid, p_fecha timestamptz DEFAULT now())
RETURNS public.calculos
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_param    public.criterios_parametros%ROWTYPE;
  v_n        integer := 0;
  v_faltan   jsonb := '[]'::jsonb;
  v_entradas jsonb := '[]'::jsonb;
  v_suma     numeric := 0;
  v_hay_est  boolean := false;
  r          record;
  v_res      public.calculos%ROWTYPE;
BEGIN
  IF NOT public.es_miembro_finca(p_finca) THEN
    RAISE EXCEPTION 'Sin acceso a la finca indicada' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lotes_ganaderos WHERE id = p_lote AND finca_id = p_finca AND NOT is_deleted) THEN
    RAISE EXCEPTION 'el lote no existe en la finca indicada' USING ERRCODE = 'integrity_constraint_violation';
  END IF;

  -- criterio vigente a la fecha
  SELECT * INTO v_param FROM public.criterios_parametros
   WHERE finca_id = p_finca AND codigo = 'ms_pct_peso_vivo' AND NOT is_deleted AND vigente_desde <= p_fecha
   ORDER BY vigente_desde DESC LIMIT 1;
  IF NOT FOUND THEN
    v_faltan := v_faltan || jsonb_build_object('falta', 'criterio_ms_pct_peso_vivo',
                 'detalle', 'no hay criterio vigente; defínalo en configuración (pendiente de verificación)');
  END IF;

  -- animales del lote a la fecha y su último peso aceptable a esa fecha
  FOR r IN
    SELECT al.animal_id, a.numero_interno,
           p.id AS pesaje_id, p.valor, p.naturaleza, p.fecha_pesaje, p.estado_calidad
      FROM public.animal_lote al
      JOIN public.animales a ON a.id = al.animal_id
      LEFT JOIN LATERAL (
        SELECT * FROM public.pesajes p
         WHERE p.animal_id = al.animal_id AND NOT p.is_deleted AND p.fecha_pesaje <= p_fecha
           AND p.estado_calidad NOT IN ('rechazado','reemplazado','inconsistente')
         ORDER BY p.fecha_pesaje DESC LIMIT 1) p ON true
     WHERE al.lote_id = p_lote AND al.finca_id = p_finca AND NOT al.is_deleted
       AND al.fecha_ingreso <= p_fecha AND (al.fecha_salida IS NULL OR al.fecha_salida > p_fecha)
     ORDER BY a.numero_interno
  LOOP
    v_n := v_n + 1;
    IF r.valor IS NULL THEN
      v_faltan := v_faltan || jsonb_build_object('falta', 'peso_animal', 'animal_id', r.animal_id,
                   'numero_interno', r.numero_interno);
    ELSE
      v_suma := v_suma + r.valor;
      IF r.naturaleza <> 'medido' THEN v_hay_est := true; END IF;
      v_entradas := v_entradas || jsonb_build_object('animal_id', r.animal_id, 'numero_interno', r.numero_interno,
                     'pesaje_id', r.pesaje_id, 'peso_kg', r.valor, 'naturaleza', r.naturaleza,
                     'fecha_pesaje', r.fecha_pesaje, 'estado_calidad', r.estado_calidad);
    END IF;
  END LOOP;

  IF v_n = 0 THEN
    v_faltan := v_faltan || jsonb_build_object('falta', 'lote_sin_animales',
                 'detalle', 'el lote no tiene animales a esa fecha; no aplica calcular (no es 0)');
  END IF;

  IF jsonb_array_length(v_faltan) > 0 THEN
    INSERT INTO public.calculos (finca_id, codigo_calculo, version_formula, formula, alcance_tipo, alcance_id,
                                 periodo_fecha, resultado, parametro_id, entradas, faltantes, calculado_por)
    VALUES (p_finca, 'demanda_ms_lote', 'demanda_ms_lote.v1',
            'SUM(peso_vivo_kg) * pct_peso_vivo / 100', 'lote', p_lote, p_fecha, 'no_calculable',
            v_param.id, jsonb_build_object('animales_en_lote', v_n, 'pesos_usados', v_entradas),
            v_faltan, auth.uid())
    RETURNING * INTO v_res;
    RETURN v_res;
  END IF;

  INSERT INTO public.calculos (finca_id, codigo_calculo, version_formula, formula, alcance_tipo, alcance_id,
                               periodo_fecha, resultado, valor, unidad, parametro_id, entradas, incertidumbre, calculado_por)
  VALUES (p_finca, 'demanda_ms_lote', 'demanda_ms_lote.v1',
          'SUM(peso_vivo_kg) * pct_peso_vivo / 100', 'lote', p_lote, p_fecha, 'calculado',
          round(v_suma * v_param.valor / 100, 3), 'kg MS/día', v_param.id,
          jsonb_build_object('animales_en_lote', v_n, 'peso_total_kg', v_suma,
                             'pct_peso_vivo', v_param.valor, 'pesos_usados', v_entradas),
          CASE WHEN v_hay_est THEN 'incluye pesos no medidos (estimado/observado/etc.); el resultado hereda esa incertidumbre' END,
          auth.uid())
  RETURNING * INTO v_res;
  RETURN v_res;
END $$;

DO $$
DECLARE t text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON public.criterios_parametros, public.calculos FROM anon';
    EXECUTE 'REVOKE ALL ON FUNCTION public.calcular_demanda_ms_lote(uuid,uuid,timestamptz) FROM anon, public';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN RETURN; END IF;
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.calcular_demanda_ms_lote(uuid,uuid,timestamptz) TO authenticated';
  EXECUTE 'REVOKE DELETE, TRUNCATE ON public.criterios_parametros, public.calculos FROM authenticated';
  FOREACH t IN ARRAY ARRAY['criterios_parametros','calculos'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS p09_%s_select ON public.%I', t, t);
    EXECUTE format('CREATE POLICY p09_%s_select ON public.%I FOR SELECT TO authenticated
                    USING (public.es_miembro_finca(finca_id))', t, t);
    EXECUTE format('DROP POLICY IF EXISTS p09_%s_insert ON public.%I', t, t);
    EXECUTE format('CREATE POLICY p09_%s_insert ON public.%I FOR INSERT TO authenticated
                    WITH CHECK (public.es_miembro_finca(finca_id))', t, t);
    EXECUTE format('DROP POLICY IF EXISTS p09_%s_update ON public.%I', t, t);
    EXECUTE format('CREATE POLICY p09_%s_update ON public.%I FOR UPDATE TO authenticated
                    USING (public.es_miembro_finca(finca_id)) WITH CHECK (public.es_miembro_finca(finca_id))', t, t);
  END LOOP;
END $$;
