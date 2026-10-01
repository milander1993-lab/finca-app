-- ============================================================================
-- 00006_guias_tecnicas.sql — Estructura de Guías/Procedimientos versionados
-- ADITIVA e idempotente. Requiere 00002.
--
-- Base: REGLA DE ORO TÉCNICA (toda medición/procedimiento debe tener una guía),
-- D-010 (las guías se versionan; lo publicado no se reescribe) y 34.16 (la
-- estructura está CERRADA; el contenido se desarrolla progresivamente).
--
-- Esta migración crea SOLO la estructura. NO contiene ninguna guía: el contenido
-- técnico debe venir de fuentes profesionales validadas (34.16/34.18/34.19).
-- ============================================================================

DO $$ BEGIN
  IF to_regclass('public.finca_miembros') IS NULL OR to_regclass('public.pesajes') IS NULL THEN
    RAISE EXCEPTION '00006 requiere 00002.';
  END IF;
END $$;

-- Guía = identidad estable (p. ej. "pesaje de bovinos"); su contenido vive en versiones.
CREATE TABLE IF NOT EXISTS public.guias (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id    uuid NOT NULL REFERENCES public.fincas(id),
  codigo      text NOT NULL CHECK (btrim(codigo) <> ''),
  titulo      text NOT NULL CHECK (btrim(titulo) <> ''),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  created_by  uuid REFERENCES auth.users(id),
  updated_by  uuid REFERENCES auth.users(id),
  version     integer NOT NULL DEFAULT 1,
  is_deleted  boolean NOT NULL DEFAULT false
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_guias_finca_codigo
  ON public.guias (finca_id, lower(codigo)) WHERE NOT is_deleted;

-- Versión = contenido con los 16 elementos de la regla de oro. Todos son texto
-- opcional mientras sea borrador: "no disponible" es un estado válido, no un relleno.
CREATE TABLE IF NOT EXISTS public.guia_versiones (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id           uuid NOT NULL REFERENCES public.fincas(id),
  guia_id            uuid NOT NULL REFERENCES public.guias(id),
  numero             integer NOT NULL CHECK (numero > 0),
  estado             text NOT NULL DEFAULT 'borrador'
                       CHECK (estado IN ('borrador','en_revision','publicada','reemplazada','anulada')),
  -- los 16 elementos de la regla de oro
  que_es             text,
  para_que           text,
  por_que            text,
  donde              text,
  como               text,
  metodo             text,
  materiales         text,
  unidades           text,
  pasos              text,
  precauciones       text,
  errores_comunes    text,
  prohibiciones      text,
  registro           text,
  evidencia          text,
  validacion         text,
  seguimiento        text,
  -- trazabilidad de la fuente (nunca se presenta como verdad sin fuente)
  fuente             text,
  revisado_por       uuid REFERENCES auth.users(id),
  publicada_en       timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  created_by         uuid REFERENCES auth.users(id),
  updated_by         uuid REFERENCES auth.users(id),
  version            integer NOT NULL DEFAULT 1,
  is_deleted         boolean NOT NULL DEFAULT false,
  UNIQUE (guia_id, numero)
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_guia_version_publicada
  ON public.guia_versiones (guia_id) WHERE estado = 'publicada' AND NOT is_deleted;

CREATE OR REPLACE FUNCTION public.guia_versiones_reglas()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_faltan text[];
  v_guia_finca uuid;
BEGIN
  SELECT finca_id INTO v_guia_finca FROM public.guias WHERE id = NEW.guia_id;
  IF v_guia_finca IS DISTINCT FROM NEW.finca_id THEN
    RAISE EXCEPTION 'la guía no pertenece a la finca indicada' USING ERRCODE = 'integrity_constraint_violation';
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.guia_id IS DISTINCT FROM OLD.guia_id OR NEW.numero IS DISTINCT FROM OLD.numero THEN
      RAISE EXCEPTION 'guia_id y numero no cambian' USING ERRCODE = 'restrict_violation';
    END IF;
    -- Lo publicado o reemplazado no se edita (D-010): solo puede pasar a
    -- 'reemplazada' (al publicarse otra) o 'anulada'. Corregir = nueva versión.
    IF OLD.estado IN ('publicada','reemplazada','anulada') THEN
      IF (to_jsonb(NEW) - ARRAY['estado','updated_at','updated_by','version','is_deleted'])
         IS DISTINCT FROM
         (to_jsonb(OLD) - ARRAY['estado','updated_at','updated_by','version','is_deleted']) THEN
        RAISE EXCEPTION 'una versión publicada no se edita: cree una versión nueva (D-010)' USING ERRCODE = 'restrict_violation';
      END IF;
      IF NOT (   (OLD.estado = 'publicada'   AND NEW.estado IN ('publicada','reemplazada','anulada'))
              OR (OLD.estado = 'reemplazada' AND NEW.estado IN ('reemplazada','anulada'))
              OR (OLD.estado = 'anulada'     AND NEW.estado = 'anulada')) THEN
        RAISE EXCEPTION 'transición no permitida: % -> %', OLD.estado, NEW.estado USING ERRCODE = 'check_violation';
      END IF;
    END IF;
  END IF;

  -- Publicar exige los 16 elementos, fuente y revisor: no se publica una guía incompleta.
  IF NEW.estado = 'publicada' AND (TG_OP = 'INSERT' OR OLD.estado <> 'publicada') THEN
    SELECT array_agg(c) INTO v_faltan FROM (VALUES
      ('que_es', NEW.que_es), ('para_que', NEW.para_que), ('por_que', NEW.por_que), ('donde', NEW.donde),
      ('como', NEW.como), ('metodo', NEW.metodo), ('materiales', NEW.materiales), ('unidades', NEW.unidades),
      ('pasos', NEW.pasos), ('precauciones', NEW.precauciones), ('errores_comunes', NEW.errores_comunes),
      ('prohibiciones', NEW.prohibiciones), ('registro', NEW.registro), ('evidencia', NEW.evidencia),
      ('validacion', NEW.validacion), ('seguimiento', NEW.seguimiento), ('fuente', NEW.fuente)
    ) AS t(c, v) WHERE v IS NULL OR btrim(v) = '';
    IF v_faltan IS NOT NULL THEN
      RAISE EXCEPTION 'no se publica una guía incompleta; faltan: %', array_to_string(v_faltan, ', ')
        USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.revisado_por IS NULL THEN
      RAISE EXCEPTION 'publicar exige revisado_por' USING ERRCODE = 'check_violation';
    END IF;
    NEW.publicada_en := now();
  END IF;
  RETURN NEW;
END $$;

-- Al publicar una versión, la publicada anterior de la misma guía pasa a 'reemplazada'
-- (se hace ANTES de validar, dentro de la misma transacción: si la nueva falla, todo se revierte).
CREATE OR REPLACE FUNCTION public.guia_versiones_liberar_publicada()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  -- antes de publicar la nueva, la anterior debe dejar de estar 'publicada' (índice único parcial)
  IF NEW.estado = 'publicada' AND (TG_OP = 'INSERT' OR OLD.estado <> 'publicada') THEN
    UPDATE public.guia_versiones
       SET estado = 'reemplazada'
     WHERE guia_id = NEW.guia_id AND id <> NEW.id AND estado = 'publicada' AND NOT is_deleted;
  END IF;
  RETURN NEW;
END $$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['guias','guia_versiones'] LOOP
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
    EXECUTE format('DROP TRIGGER IF EXISTS t90_auditar ON public.%I', t);
    EXECUTE format('CREATE TRIGGER t90_auditar AFTER INSERT OR UPDATE ON public.%I
                    FOR EACH ROW EXECUTE FUNCTION public.auditar_cambio()', t);
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
  END LOOP;
END $$;

DROP TRIGGER IF EXISTS t45_guia_liberar ON public.guia_versiones;
CREATE TRIGGER t45_guia_liberar BEFORE INSERT OR UPDATE ON public.guia_versiones
  FOR EACH ROW EXECUTE FUNCTION public.guia_versiones_liberar_publicada();
DROP TRIGGER IF EXISTS t50_guia_reglas ON public.guia_versiones;
CREATE TRIGGER t50_guia_reglas BEFORE INSERT OR UPDATE ON public.guia_versiones
  FOR EACH ROW EXECUTE FUNCTION public.guia_versiones_reglas();

DO $$
DECLARE t text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON public.guias, public.guia_versiones FROM anon';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN RETURN; END IF;
  EXECUTE 'REVOKE DELETE, TRUNCATE ON public.guias, public.guia_versiones FROM authenticated';
  FOREACH t IN ARRAY ARRAY['guias','guia_versiones'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS p06_%s_select ON public.%I', t, t);
    EXECUTE format('CREATE POLICY p06_%s_select ON public.%I FOR SELECT TO authenticated
                    USING (public.es_miembro_finca(finca_id))', t, t);
    EXECUTE format('DROP POLICY IF EXISTS p06_%s_insert ON public.%I', t, t);
    EXECUTE format('CREATE POLICY p06_%s_insert ON public.%I FOR INSERT TO authenticated
                    WITH CHECK (public.es_miembro_finca(finca_id))', t, t);
    EXECUTE format('DROP POLICY IF EXISTS p06_%s_update ON public.%I', t, t);
    EXECUTE format('CREATE POLICY p06_%s_update ON public.%I FOR UPDATE TO authenticated
                    USING (public.es_miembro_finca(finca_id)) WITH CHECK (public.es_miembro_finca(finca_id))', t, t);
  END LOOP;
END $$;
