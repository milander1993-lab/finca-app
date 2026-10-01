-- ============================================================================
-- 00011_aforo_muestras_agua.sql — Aforo con VARIOS puntos de muestreo + % de agua
-- ADITIVA e idempotente. Requiere 00007 (aforos) y 00008.
--
-- Regla del usuario (30-sep): la materia seca se mide cuando se corta el metro
-- cuadrado en varios puntos del potrero. %MS = materia seca / materia fresca × 100
-- y el sistema debe poder decir cuánta AGUA tiene el pasto: %agua = 100 − %MS.
--
-- Un aforo (cabecera) = una visita a un potrero/división; cada punto cortado es una
-- fila en aforo_muestras. El tamaño de la parcela (p. ej. 1 m²) NO se fija aquí: se
-- registra por punto. La materia seca se anota después del secado (puede ser NULL
-- al inicio: pendiente, no 0). El método detallado sigue ligado a una guía (34.6).
-- ============================================================================
DO $$ BEGIN
  IF to_regclass('public.aforos') IS NULL OR NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'estado_calidad_dato') THEN
    RAISE EXCEPTION '00011 requiere 00007 y 00008.';
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.aforo_muestras (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id         uuid NOT NULL REFERENCES public.fincas(id),
  aforo_id         uuid NOT NULL REFERENCES public.aforos(id),
  punto            integer NOT NULL CHECK (punto > 0),            -- 1, 2, 3...
  area_muestra_m2  numeric(10,3) CHECK (area_muestra_m2 IS NULL OR area_muestra_m2 > 0),
  materia_fresca_g numeric(12,3) CHECK (materia_fresca_g IS NULL OR materia_fresca_g > 0),
  materia_seca_g   numeric(12,3) CHECK (materia_seca_g IS NULL OR materia_seca_g > 0),
  observaciones    text,
  estado_calidad   public.estado_calidad_dato NOT NULL DEFAULT 'registrado',
  nota_calidad     text,
  sincronizada_en  timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  created_by       uuid REFERENCES auth.users(id),
  updated_by       uuid REFERENCES auth.users(id),
  version          integer NOT NULL DEFAULT 1,
  is_deleted       boolean NOT NULL DEFAULT false,
  CHECK (materia_seca_g IS NULL OR materia_fresca_g IS NULL OR materia_seca_g <= materia_fresca_g)
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_aforo_muestra_punto
  ON public.aforo_muestras (aforo_id, punto) WHERE NOT is_deleted;

CREATE OR REPLACE FUNCTION public.aforo_muestras_reglas()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF (SELECT finca_id FROM public.aforos WHERE id = NEW.aforo_id) IS DISTINCT FROM NEW.finca_id THEN
    RAISE EXCEPTION 'el aforo no pertenece a la finca indicada' USING ERRCODE = 'integrity_constraint_violation';
  END IF;
  IF TG_OP = 'UPDATE' THEN
    -- lo cortado/pesado en fresco no se reescribe; la MS se anota una vez (tras el secado)
    IF NEW.aforo_id IS DISTINCT FROM OLD.aforo_id OR NEW.punto IS DISTINCT FROM OLD.punto
       OR NEW.area_muestra_m2 IS DISTINCT FROM OLD.area_muestra_m2
       OR NEW.materia_fresca_g IS DISTINCT FROM OLD.materia_fresca_g THEN
      RAISE EXCEPTION 'un punto de muestreo no se reescribe: anule y registre de nuevo' USING ERRCODE = 'restrict_violation';
    END IF;
    IF OLD.materia_seca_g IS NOT NULL AND NEW.materia_seca_g IS DISTINCT FROM OLD.materia_seca_g THEN
      RAISE EXCEPTION 'la materia seca ya fue registrada: anule y registre de nuevo' USING ERRCODE = 'restrict_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;

DO $$
BEGIN
  EXECUTE 'DROP TRIGGER IF EXISTS t10_sellar_autoria ON public.aforo_muestras';
  EXECUTE 'CREATE TRIGGER t10_sellar_autoria BEFORE INSERT OR UPDATE ON public.aforo_muestras
           FOR EACH ROW EXECUTE FUNCTION public.sellar_autoria()';
  IF NOT EXISTS (SELECT 1 FROM pg_trigger g WHERE g.tgrelid = 'public.aforo_muestras'::regclass
                 AND NOT g.tgisinternal AND g.tgfoid = 'public.actualizar_timestamps()'::regprocedure) THEN
    EXECUTE 'CREATE TRIGGER t20_timestamps BEFORE UPDATE ON public.aforo_muestras
             FOR EACH ROW EXECUTE FUNCTION public.actualizar_timestamps()';
  END IF;
  EXECUTE 'DROP TRIGGER IF EXISTS t12_sincronizacion_ins ON public.aforo_muestras';
  EXECUTE 'CREATE TRIGGER t12_sincronizacion_ins BEFORE INSERT ON public.aforo_muestras
           FOR EACH ROW EXECUTE FUNCTION public.sellar_sincronizacion()';
  EXECUTE 'DROP TRIGGER IF EXISTS t12_sincronizacion_upd ON public.aforo_muestras';
  EXECUTE 'CREATE TRIGGER t12_sincronizacion_upd BEFORE UPDATE ON public.aforo_muestras
           FOR EACH ROW EXECUTE FUNCTION public.proteger_sincronizacion()';
  EXECUTE 'DROP TRIGGER IF EXISTS t30_bloquear_delete ON public.aforo_muestras';
  EXECUTE 'CREATE TRIGGER t30_bloquear_delete BEFORE DELETE ON public.aforo_muestras
           FOR EACH ROW EXECUTE FUNCTION public.bloquear_delete()';
  EXECUTE 'DROP TRIGGER IF EXISTS t50_aforo_muestras_reglas ON public.aforo_muestras';
  EXECUTE 'CREATE TRIGGER t50_aforo_muestras_reglas BEFORE INSERT OR UPDATE ON public.aforo_muestras
           FOR EACH ROW EXECUTE FUNCTION public.aforo_muestras_reglas()';
  EXECUTE 'DROP TRIGGER IF EXISTS t55_calidad_dato ON public.aforo_muestras';
  EXECUTE 'CREATE TRIGGER t55_calidad_dato BEFORE INSERT OR UPDATE ON public.aforo_muestras
           FOR EACH ROW EXECUTE FUNCTION public.calidad_dato_reglas()';
  EXECUTE 'DROP TRIGGER IF EXISTS t90_auditar ON public.aforo_muestras';
  EXECUTE 'CREATE TRIGGER t90_auditar AFTER INSERT OR UPDATE ON public.aforo_muestras
           FOR EACH ROW EXECUTE FUNCTION public.auditar_cambio()';
  EXECUTE 'ALTER TABLE public.aforo_muestras ENABLE ROW LEVEL SECURITY';
END $$;

-- Vista de un solo punto (compatibilidad): añade %agua (columnas nuevas al final)
CREATE OR REPLACE VIEW public.v_aforos_calculo
WITH (security_invoker = true) AS
SELECT
  a.id, a.finca_id, a.unidad_id, a.fecha_aforo, a.naturaleza, a.guia_version_id,
  CASE WHEN a.materia_seca_g IS NOT NULL AND a.materia_fresca_g IS NOT NULL
       THEN round((a.materia_seca_g / a.materia_fresca_g * 100)::numeric, 2) END AS ms_pct_calculado,
  CASE WHEN a.materia_seca_g IS NOT NULL AND a.area_muestra_m2 IS NOT NULL
       THEN round((a.materia_seca_g / a.area_muestra_m2)::numeric, 2) END AS ms_g_por_m2_calculado,
  CASE WHEN a.materia_seca_g IS NULL OR a.materia_fresca_g IS NULL THEN 'no_calculable' ELSE 'calculado' END AS estado_ms_pct,
  CASE WHEN a.materia_seca_g IS NOT NULL AND a.materia_fresca_g IS NOT NULL
       THEN round((100 - a.materia_seca_g / a.materia_fresca_g * 100)::numeric, 2) END AS agua_pct_calculado
FROM public.aforos a
WHERE NOT a.is_deleted;

-- Resumen del aforo (todos los puntos):
--   %MS    = ΣMS / ΣMF × 100   (solo puntos con MF y MS; ponderado por masa)
--   %agua  = 100 − %MS
--   MS por m² = ΣMS / Σárea (solo puntos con MS y área)
--   kg MS/ha  = g/m² × 10     (conversión de unidades: 1 g/m² = 10 kg/ha)
-- Un aforo antiguo sin puntos usa los valores de su cabecera como un solo punto.
-- Sin datos indispensables => NULL + estado 'no_calculable' (nunca 0).
CREATE OR REPLACE VIEW public.v_aforos_resumen
WITH (security_invoker = true) AS
WITH puntos AS (
  SELECT m.aforo_id, m.punto, m.area_muestra_m2 AS area, m.materia_fresca_g AS mf, m.materia_seca_g AS ms
    FROM public.aforo_muestras m
   WHERE NOT m.is_deleted AND m.estado_calidad NOT IN ('rechazado','reemplazado','inconsistente')
  UNION ALL
  SELECT a.id, 1, a.area_muestra_m2, a.materia_fresca_g, a.materia_seca_g
    FROM public.aforos a
   WHERE NOT a.is_deleted
     AND NOT EXISTS (SELECT 1 FROM public.aforo_muestras m WHERE m.aforo_id = a.id AND NOT m.is_deleted)
), agg AS (
  SELECT aforo_id,
         count(*) AS n_puntos,
         count(*) FILTER (WHERE mf IS NOT NULL AND ms IS NOT NULL) AS n_puntos_con_ms,
         sum(mf)  FILTER (WHERE mf IS NOT NULL AND ms IS NOT NULL) AS mf_total_g,
         sum(ms)  FILTER (WHERE mf IS NOT NULL AND ms IS NOT NULL) AS ms_total_g,
         sum(area) FILTER (WHERE area IS NOT NULL AND ms IS NOT NULL) AS area_con_ms_m2,
         sum(ms)  FILTER (WHERE area IS NOT NULL AND ms IS NOT NULL) AS ms_con_area_g,
         min(ms / mf * 100) FILTER (WHERE mf IS NOT NULL AND ms IS NOT NULL) AS ms_pct_min_punto,
         max(ms / mf * 100) FILTER (WHERE mf IS NOT NULL AND ms IS NOT NULL) AS ms_pct_max_punto
    FROM puntos GROUP BY aforo_id
)
SELECT a.id AS aforo_id, a.finca_id, a.unidad_id, a.fecha_aforo, a.naturaleza,
       g.n_puntos, g.n_puntos_con_ms,
       CASE WHEN g.n_puntos_con_ms > 0 THEN round((g.ms_total_g / g.mf_total_g * 100)::numeric, 2) END AS ms_pct,
       CASE WHEN g.n_puntos_con_ms > 0 THEN round((100 - g.ms_total_g / g.mf_total_g * 100)::numeric, 2) END AS agua_pct,
       CASE WHEN g.n_puntos_con_ms > 0 THEN round(g.ms_pct_min_punto::numeric, 2) END AS ms_pct_min_punto,
       CASE WHEN g.n_puntos_con_ms > 0 THEN round(g.ms_pct_max_punto::numeric, 2) END AS ms_pct_max_punto,
       CASE WHEN g.area_con_ms_m2 > 0 THEN round((g.ms_con_area_g / g.area_con_ms_m2)::numeric, 2) END AS ms_g_por_m2,
       CASE WHEN g.area_con_ms_m2 > 0 THEN round((g.ms_con_area_g / g.area_con_ms_m2 * 10)::numeric, 1) END AS ms_kg_por_ha,
       CASE WHEN g.n_puntos_con_ms > 0 THEN 'calculado' ELSE 'no_calculable' END AS estado_ms_pct,
       CASE WHEN g.n_puntos_con_ms > 0 AND g.n_puntos_con_ms < g.n_puntos
            THEN 'hay puntos sin materia seca registrada: el resultado usa solo los puntos completos' END AS advertencia
  FROM public.aforos a
  LEFT JOIN agg g ON g.aforo_id = a.id
 WHERE NOT a.is_deleted;

DO $$
DECLARE t text := 'aforo_muestras';
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON public.aforo_muestras, public.v_aforos_resumen FROM anon';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN RETURN; END IF;
  EXECUTE 'REVOKE DELETE, TRUNCATE ON public.aforo_muestras FROM authenticated';
  EXECUTE 'REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.v_aforos_resumen FROM authenticated';
  EXECUTE 'GRANT SELECT ON public.v_aforos_resumen, public.v_aforos_calculo TO authenticated';
  EXECUTE 'DROP POLICY IF EXISTS p11_muestras_select ON public.aforo_muestras';
  EXECUTE 'CREATE POLICY p11_muestras_select ON public.aforo_muestras FOR SELECT TO authenticated
           USING (public.es_miembro_finca(finca_id))';
  EXECUTE 'DROP POLICY IF EXISTS p11_muestras_insert ON public.aforo_muestras';
  EXECUTE 'CREATE POLICY p11_muestras_insert ON public.aforo_muestras FOR INSERT TO authenticated
           WITH CHECK (public.es_miembro_finca(finca_id))';
  EXECUTE 'DROP POLICY IF EXISTS p11_muestras_update ON public.aforo_muestras';
  EXECUTE 'CREATE POLICY p11_muestras_update ON public.aforo_muestras FOR UPDATE TO authenticated
           USING (public.es_miembro_finca(finca_id)) WITH CHECK (public.es_miembro_finca(finca_id))';
END $$;
