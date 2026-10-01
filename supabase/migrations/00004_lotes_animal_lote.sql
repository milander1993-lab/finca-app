-- ============================================================================
-- 00004_lotes_animal_lote.sql — Iteración 1: lotes y pertenencia HISTÓRICA
-- ADITIVA e idempotente. Requiere 00002.
--
-- DT-011 (decisión automática): la brecha CHG-008 dice que `lotes_ganaderos`
-- figuraba en V3 pero no en el SQL pegado. Se crea SOLO SI NO EXISTE, con columnas
-- mínimas. Si ya existe en tu base real, no se toca: hay que revisar que tenga
-- `id uuid` como clave y `finca_id`; si difiere, avisar (PREAPROBACIÓN REQUERIDA).
--
-- Regla: un animal está en a lo sumo UN lote a la vez; los cambios quedan como
-- historia (ingreso/salida), nunca se sobrescribe ni se borra.
-- ============================================================================

DO $$ BEGIN
  IF to_regclass('public.finca_miembros') IS NULL OR to_regclass('public.pesajes') IS NULL THEN
    RAISE EXCEPTION '00004 requiere 00002.';
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.lotes_ganaderos (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id    uuid NOT NULL REFERENCES public.fincas(id),
  nombre      text NOT NULL CHECK (btrim(nombre) <> ''),
  estado      varchar(20) NOT NULL DEFAULT 'activo',
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  created_by  uuid REFERENCES auth.users(id),
  updated_by  uuid REFERENCES auth.users(id),
  version     integer NOT NULL DEFAULT 1,
  is_deleted  boolean NOT NULL DEFAULT false
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_lotes_finca_nombre
  ON public.lotes_ganaderos (finca_id, lower(nombre)) WHERE NOT is_deleted;

CREATE TABLE IF NOT EXISTS public.animal_lote (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id        uuid NOT NULL REFERENCES public.fincas(id),
  animal_id       uuid NOT NULL REFERENCES public.animales(id),
  lote_id         uuid NOT NULL REFERENCES public.lotes_ganaderos(id),
  fecha_ingreso   timestamptz NOT NULL,
  fecha_salida    timestamptz,
  motivo_ingreso  text,
  motivo_salida   text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  created_by      uuid REFERENCES auth.users(id),
  updated_by      uuid REFERENCES auth.users(id),
  version         integer NOT NULL DEFAULT 1,
  is_deleted      boolean NOT NULL DEFAULT false,
  CHECK (fecha_salida IS NULL OR fecha_salida >= fecha_ingreso)
);

-- un solo lote abierto por animal
CREATE UNIQUE INDEX IF NOT EXISTS ux_animal_lote_abierto
  ON public.animal_lote (animal_id) WHERE fecha_salida IS NULL AND NOT is_deleted;
CREATE INDEX IF NOT EXISTS ix_animal_lote_lote
  ON public.animal_lote (lote_id) WHERE fecha_salida IS NULL AND NOT is_deleted;
CREATE INDEX IF NOT EXISTS ix_animal_lote_animal
  ON public.animal_lote (animal_id, fecha_ingreso DESC);

-- coherencia: animal y lote de la misma finca; lo ocurrido no se reescribe
CREATE OR REPLACE FUNCTION public.animal_lote_coherencia()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF (SELECT finca_id FROM public.animales WHERE id = NEW.animal_id) IS DISTINCT FROM NEW.finca_id
       OR (SELECT finca_id FROM public.lotes_ganaderos WHERE id = NEW.lote_id) IS DISTINCT FROM NEW.finca_id THEN
      RAISE EXCEPTION 'animal y lote deben pertenecer a la finca indicada'
        USING ERRCODE = 'integrity_constraint_violation';
    END IF;
    IF NEW.fecha_ingreso > now() + interval '10 minutes' THEN
      RAISE EXCEPTION 'fecha_ingreso en el futuro' USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.animal_id IS DISTINCT FROM OLD.animal_id OR NEW.lote_id IS DISTINCT FROM OLD.lote_id
     OR NEW.fecha_ingreso IS DISTINCT FROM OLD.fecha_ingreso
     OR NEW.motivo_ingreso IS DISTINCT FROM OLD.motivo_ingreso THEN
    RAISE EXCEPTION 'la pertenencia a un lote no se reescribe: solo se cierra (fecha_salida)'
      USING ERRCODE = 'restrict_violation';
  END IF;
  IF OLD.fecha_salida IS NOT NULL
     AND (NEW.fecha_salida IS DISTINCT FROM OLD.fecha_salida OR NEW.motivo_salida IS DISTINCT FROM OLD.motivo_salida) THEN
    RAISE EXCEPTION 'la pertenencia ya fue cerrada' USING ERRCODE = 'restrict_violation';
  END IF;
  IF NEW.fecha_salida IS NOT NULL AND btrim(coalesce(NEW.motivo_salida, '')) = '' THEN
    RAISE EXCEPTION 'cerrar la pertenencia exige motivo' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['lotes_ganaderos','animal_lote'] LOOP
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

DROP TRIGGER IF EXISTS t50_animal_lote ON public.animal_lote;
CREATE TRIGGER t50_animal_lote BEFORE INSERT OR UPDATE ON public.animal_lote
  FOR EACH ROW EXECUTE FUNCTION public.animal_lote_coherencia();

DO $$
DECLARE t text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON public.lotes_ganaderos, public.animal_lote FROM anon';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN RETURN; END IF;
  EXECUTE 'REVOKE DELETE, TRUNCATE ON public.lotes_ganaderos, public.animal_lote FROM authenticated';
  FOREACH t IN ARRAY ARRAY['lotes_ganaderos','animal_lote'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS p04_%s_select ON public.%I', t, t);
    EXECUTE format('CREATE POLICY p04_%s_select ON public.%I FOR SELECT TO authenticated
                    USING (public.es_miembro_finca(finca_id))', t, t);
    EXECUTE format('DROP POLICY IF EXISTS p04_%s_insert ON public.%I', t, t);
    EXECUTE format('CREATE POLICY p04_%s_insert ON public.%I FOR INSERT TO authenticated
                    WITH CHECK (public.es_miembro_finca(finca_id))', t, t);
    EXECUTE format('DROP POLICY IF EXISTS p04_%s_update ON public.%I', t, t);
    EXECUTE format('CREATE POLICY p04_%s_update ON public.%I FOR UPDATE TO authenticated
                    USING (public.es_miembro_finca(finca_id)) WITH CHECK (public.es_miembro_finca(finca_id))', t, t);
  END LOOP;
END $$;
