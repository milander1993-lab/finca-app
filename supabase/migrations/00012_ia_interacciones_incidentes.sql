-- ============================================================================
-- 00012_ia_interacciones_incidentes.sql — ADITIVA e idempotente. Requiere 00008.
-- 1) ia_interacciones: registro de TODA función de IA (prompt §60): contexto, entrada,
--    salida, usuario, fecha, modelo, versión, incertidumbre, datos consultados y la
--    acción humana posterior. Solo se anota; la salida no se reescribe.
--    La IA propone; esta tabla NO ejecuta nada ni modifica datos críticos.
-- 2) incidentes_tecnicos: errores de sincronización/datos/sistema con estado (§66).
-- No se define proveedor ni modelo de IA (pendiente 3.9): son texto libre.
-- ============================================================================
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'estado_calidad_dato') THEN
    RAISE EXCEPTION '00012 requiere 00008.';
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.ia_interacciones (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id           uuid NOT NULL REFERENCES public.fincas(id),
  funcion            text NOT NULL CHECK (btrim(funcion) <> ''),   -- p. ej. 'explicar_guia'
  contexto           jsonb NOT NULL DEFAULT '{}'::jsonb,           -- qué pantalla/entidad
  entrada            text NOT NULL,
  salida             text,
  datos_consultados  jsonb,                                        -- qué tablas/filas leyó
  incertidumbre      text,
  modelo             text,
  version_modelo     text,
  estado             text NOT NULL DEFAULT 'registrada'
                       CHECK (estado IN ('registrada','revisada','aceptada','descartada','fallida')),
  accion_humana      text,
  accion_humana_en   timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  created_by         uuid REFERENCES auth.users(id),
  updated_by         uuid REFERENCES auth.users(id),
  version            integer NOT NULL DEFAULT 1,
  is_deleted         boolean NOT NULL DEFAULT false,
  sincronizada_en    timestamptz
);

CREATE TABLE IF NOT EXISTS public.incidentes_tecnicos (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id     uuid NOT NULL REFERENCES public.fincas(id),
  tipo         text NOT NULL CHECK (tipo IN ('sincronizacion','datos','sistema','seguridad','otro')),
  severidad    text NOT NULL DEFAULT 'media' CHECK (severidad IN ('baja','media','alta')),
  titulo       text NOT NULL CHECK (btrim(titulo) <> ''),
  descripcion  text,
  origen       jsonb,                      -- tabla/fila/operación implicada
  estado       text NOT NULL DEFAULT 'abierto' CHECK (estado IN ('abierto','en_analisis','resuelto','cerrado')),
  resolucion   text,
  cerrado_en   timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  created_by   uuid REFERENCES auth.users(id),
  updated_by   uuid REFERENCES auth.users(id),
  version      integer NOT NULL DEFAULT 1,
  is_deleted   boolean NOT NULL DEFAULT false,
  sincronizada_en timestamptz
);

-- IA: lo que la IA dijo no se reescribe; solo se anota la acción humana posterior (una vez)
CREATE OR REPLACE FUNCTION public.ia_interacciones_reglas()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.funcion IS DISTINCT FROM OLD.funcion OR NEW.contexto IS DISTINCT FROM OLD.contexto
       OR NEW.entrada IS DISTINCT FROM OLD.entrada OR NEW.datos_consultados IS DISTINCT FROM OLD.datos_consultados
       OR NEW.incertidumbre IS DISTINCT FROM OLD.incertidumbre OR NEW.modelo IS DISTINCT FROM OLD.modelo
       OR NEW.version_modelo IS DISTINCT FROM OLD.version_modelo
       OR (OLD.salida IS NOT NULL AND NEW.salida IS DISTINCT FROM OLD.salida) THEN
      RAISE EXCEPTION 'el registro de IA no se reescribe (solo se anota la acción humana)' USING ERRCODE = 'restrict_violation';
    END IF;
    IF OLD.accion_humana IS NOT NULL AND NEW.accion_humana IS DISTINCT FROM OLD.accion_humana THEN
      RAISE EXCEPTION 'la acción humana ya fue registrada' USING ERRCODE = 'restrict_violation';
    END IF;
  END IF;
  -- aceptar o descartar es una decisión humana: exige quién (sellado por autoría) y texto
  IF NEW.estado IN ('aceptada','descartada') AND btrim(coalesce(NEW.accion_humana, '')) = '' THEN
    RAISE EXCEPTION 'aceptar o descartar una salida de IA exige accion_humana' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.accion_humana IS NOT NULL AND NEW.accion_humana_en IS NULL THEN
    NEW.accion_humana_en := now();
  END IF;
  RETURN NEW;
END $$;

-- Incidentes: cerrar exige resolución; un incidente cerrado no se reabre ni se reescribe
CREATE OR REPLACE FUNCTION public.incidentes_reglas()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF OLD.estado = 'cerrado' AND (to_jsonb(NEW) - ARRAY['updated_at','updated_by','version','is_deleted'])
                                  IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['updated_at','updated_by','version','is_deleted']) THEN
      RAISE EXCEPTION 'un incidente cerrado no se modifica: abra uno nuevo' USING ERRCODE = 'restrict_violation';
    END IF;
    IF NEW.tipo IS DISTINCT FROM OLD.tipo OR NEW.origen IS DISTINCT FROM OLD.origen THEN
      RAISE EXCEPTION 'tipo y origen del incidente no cambian' USING ERRCODE = 'restrict_violation';
    END IF;
  END IF;
  IF NEW.estado IN ('resuelto','cerrado') AND btrim(coalesce(NEW.resolucion, '')) = '' THEN
    RAISE EXCEPTION 'resolver o cerrar exige resolucion' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.estado = 'cerrado' AND NEW.cerrado_en IS NULL THEN NEW.cerrado_en := now(); END IF;
  RETURN NEW;
END $$;

DO $$
DECLARE t text; f text;
BEGIN
  FOREACH t IN ARRAY ARRAY['ia_interacciones','incidentes_tecnicos'] LOOP
    f := CASE t WHEN 'ia_interacciones' THEN 'ia_interacciones_reglas' ELSE 'incidentes_reglas' END;
    EXECUTE format('DROP TRIGGER IF EXISTS t10_sellar_autoria ON public.%I', t);
    EXECUTE format('CREATE TRIGGER t10_sellar_autoria BEFORE INSERT OR UPDATE ON public.%I
                    FOR EACH ROW EXECUTE FUNCTION public.sellar_autoria()', t);
    IF NOT EXISTS (SELECT 1 FROM pg_trigger g WHERE g.tgrelid = format('public.%I', t)::regclass
                   AND NOT g.tgisinternal AND g.tgfoid = 'public.actualizar_timestamps()'::regprocedure) THEN
      EXECUTE format('CREATE TRIGGER t20_timestamps BEFORE UPDATE ON public.%I
                      FOR EACH ROW EXECUTE FUNCTION public.actualizar_timestamps()', t);
    END IF;
    EXECUTE format('DROP TRIGGER IF EXISTS t12_sincronizacion_ins ON public.%I', t);
    EXECUTE format('CREATE TRIGGER t12_sincronizacion_ins BEFORE INSERT ON public.%I
                    FOR EACH ROW EXECUTE FUNCTION public.sellar_sincronizacion()', t);
    EXECUTE format('DROP TRIGGER IF EXISTS t12_sincronizacion_upd ON public.%I', t);
    EXECUTE format('CREATE TRIGGER t12_sincronizacion_upd BEFORE UPDATE ON public.%I
                    FOR EACH ROW EXECUTE FUNCTION public.proteger_sincronizacion()', t);
    EXECUTE format('DROP TRIGGER IF EXISTS t30_bloquear_delete ON public.%I', t);
    EXECUTE format('CREATE TRIGGER t30_bloquear_delete BEFORE DELETE ON public.%I
                    FOR EACH ROW EXECUTE FUNCTION public.bloquear_delete()', t);
    EXECUTE format('DROP TRIGGER IF EXISTS t50_reglas ON public.%I', t);
    EXECUTE format('CREATE TRIGGER t50_reglas BEFORE INSERT OR UPDATE ON public.%I
                    FOR EACH ROW EXECUTE FUNCTION public.%I()', t, f);
    EXECUTE format('DROP TRIGGER IF EXISTS t90_auditar ON public.%I', t);
    EXECUTE format('CREATE TRIGGER t90_auditar AFTER INSERT OR UPDATE ON public.%I
                    FOR EACH ROW EXECUTE FUNCTION public.auditar_cambio()', t);
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
  END LOOP;
END $$;

DO $$
DECLARE t text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON public.ia_interacciones, public.incidentes_tecnicos FROM anon';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN RETURN; END IF;
  EXECUTE 'REVOKE DELETE, TRUNCATE ON public.ia_interacciones, public.incidentes_tecnicos FROM authenticated';
  FOREACH t IN ARRAY ARRAY['ia_interacciones','incidentes_tecnicos'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS p12_%s_select ON public.%I', t, t);
    EXECUTE format('CREATE POLICY p12_%s_select ON public.%I FOR SELECT TO authenticated
                    USING (public.es_miembro_finca(finca_id))', t, t);
    EXECUTE format('DROP POLICY IF EXISTS p12_%s_insert ON public.%I', t, t);
    EXECUTE format('CREATE POLICY p12_%s_insert ON public.%I FOR INSERT TO authenticated
                    WITH CHECK (public.es_miembro_finca(finca_id))', t, t);
    EXECUTE format('DROP POLICY IF EXISTS p12_%s_update ON public.%I', t, t);
    EXECUTE format('CREATE POLICY p12_%s_update ON public.%I FOR UPDATE TO authenticated
                    USING (public.es_miembro_finca(finca_id)) WITH CHECK (public.es_miembro_finca(finca_id))', t, t);
  END LOOP;
END $$;
