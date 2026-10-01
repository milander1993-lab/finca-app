-- ============================================================================
-- 00010_guias_campos_prompt.sql — ADITIVA e idempotente. Requiere 00006.
-- El Prompt Maestro (§2 Regla de oro) amplía la guía: añade cuándo, quién puede
-- realizarlo, equipos, preparación, condiciones de suspensión y criterios de
-- aceptación. Se agregan como columnas; PUBLICAR exige ahora los 22 elementos
-- (si uno no aplica, se escribe explícitamente 'no aplica': nunca queda vacío).
-- No se inventa contenido de ninguna guía.
-- Las versiones ya publicadas (si existieran) no se modifican.
-- ============================================================================
DO $$ BEGIN
  IF to_regclass('public.guia_versiones') IS NULL THEN RAISE EXCEPTION '00010 requiere 00006.'; END IF;
END $$;

ALTER TABLE public.guia_versiones
  ADD COLUMN IF NOT EXISTS cuando text,
  ADD COLUMN IF NOT EXISTS quien_puede text,
  ADD COLUMN IF NOT EXISTS equipos text,
  ADD COLUMN IF NOT EXISTS preparacion text,
  ADD COLUMN IF NOT EXISTS condiciones_suspension text,
  ADD COLUMN IF NOT EXISTS criterios_aceptacion text;

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
      ('validacion', NEW.validacion), ('seguimiento', NEW.seguimiento), ('fuente', NEW.fuente),
      ('cuando', NEW.cuando), ('quien_puede', NEW.quien_puede), ('equipos', NEW.equipos),
      ('preparacion', NEW.preparacion), ('condiciones_suspension', NEW.condiciones_suspension),
      ('criterios_aceptacion', NEW.criterios_aceptacion)
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
