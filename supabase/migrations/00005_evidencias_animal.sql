-- ============================================================================
-- 00005_evidencias_animal.sql — Iteración 2 (ganadería base): evidencia fotográfica
-- ADITIVA e idempotente. Requiere 00002 (y 00004 no es necesaria).
--
-- Base: D-006 (foto principal + serie corporal estandarizada + zona específica;
-- la foto de ubre es EVIDENCIA, no diagnóstico), D-008 (archivos en Google Drive,
-- la BD guarda solo metadatos), DT-006 (el registro se guarda primero; la subida
-- a Drive va por cola en segundo plano).
--
-- NO se inventa la guía fotográfica (34.9 pendiente): los ángulos de la serie
-- corporal y las zonas se guardan como texto libre hasta que la guía los defina.
-- ============================================================================

DO $$ BEGIN
  IF to_regclass('public.finca_miembros') IS NULL OR to_regclass('public.pesajes') IS NULL THEN
    RAISE EXCEPTION '00005 requiere 00002.';
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.evidencias_animal (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),   -- generado en el cliente
  finca_id         uuid NOT NULL REFERENCES public.fincas(id),
  animal_id        uuid NOT NULL REFERENCES public.animales(id),
  -- tipos aprobados en D-006
  tipo             text NOT NULL CHECK (tipo IN ('principal','serie_corporal','zona_especifica','ubre')),
  angulo           text,                   -- serie_corporal: pendiente de guía 34.9
  zona             text,                   -- zona_especifica: pendiente de guía 34.9
  tomada_en        timestamptz NOT NULL,   -- cuándo se tomó (evento)
  naturaleza       public.naturaleza_dato NOT NULL DEFAULT 'observado',
  -- sincronización con Drive (DT-006)
  estado_subida    text NOT NULL DEFAULT 'pendiente_sincronizacion'
                     CHECK (estado_subida IN ('pendiente_sincronizacion','subida','error')),
  drive_file_id    text,
  drive_miniatura_id text,
  sha256           text CHECK (sha256 IS NULL OR sha256 ~ '^[0-9a-f]{64}$'),
  mime             text,
  bytes            bigint CHECK (bytes IS NULL OR bytes > 0),
  intentos_subida  integer NOT NULL DEFAULT 0 CHECK (intentos_subida >= 0),
  ultimo_error     text,
  observaciones    text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  created_by       uuid REFERENCES auth.users(id),
  updated_by       uuid REFERENCES auth.users(id),
  version          integer NOT NULL DEFAULT 1,
  is_deleted       boolean NOT NULL DEFAULT false,
  CHECK (estado_subida <> 'subida' OR drive_file_id IS NOT NULL),
  CHECK (angulo IS NULL OR tipo = 'serie_corporal'),
  CHECK (zona   IS NULL OR tipo IN ('zona_especifica','ubre'))
);

-- a lo sumo una foto principal vigente por animal
CREATE UNIQUE INDEX IF NOT EXISTS ux_evidencias_principal_vigente
  ON public.evidencias_animal (animal_id) WHERE tipo = 'principal' AND NOT is_deleted;
CREATE INDEX IF NOT EXISTS ix_evidencias_animal
  ON public.evidencias_animal (animal_id, tomada_en DESC) WHERE NOT is_deleted;
CREATE INDEX IF NOT EXISTS ix_evidencias_cola
  ON public.evidencias_animal (finca_id, estado_subida) WHERE estado_subida <> 'subida' AND NOT is_deleted;

-- Coherencia y reglas de inmutabilidad:
--  * el animal pertenece a la finca; no se toma una foto en el futuro;
--  * lo que se fotografió no se reescribe: solo avanza la subida y se anula.
CREATE OR REPLACE FUNCTION public.evidencias_animal_reglas()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF (SELECT finca_id FROM public.animales WHERE id = NEW.animal_id) IS DISTINCT FROM NEW.finca_id THEN
      RAISE EXCEPTION 'el animal no pertenece a la finca indicada' USING ERRCODE = 'integrity_constraint_violation';
    END IF;
    IF NEW.tomada_en > now() + interval '10 minutes' THEN
      RAISE EXCEPTION 'tomada_en en el futuro' USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.animal_id IS DISTINCT FROM OLD.animal_id OR NEW.tipo IS DISTINCT FROM OLD.tipo
     OR NEW.angulo IS DISTINCT FROM OLD.angulo OR NEW.zona IS DISTINCT FROM OLD.zona
     OR NEW.tomada_en IS DISTINCT FROM OLD.tomada_en OR NEW.naturaleza IS DISTINCT FROM OLD.naturaleza THEN
    RAISE EXCEPTION 'una evidencia no se reescribe: anule y registre de nuevo' USING ERRCODE = 'restrict_violation';
  END IF;
  IF OLD.estado_subida = 'subida' THEN
    IF NEW.estado_subida IS DISTINCT FROM OLD.estado_subida
       OR NEW.drive_file_id IS DISTINCT FROM OLD.drive_file_id
       OR NEW.sha256 IS DISTINCT FROM OLD.sha256 THEN
      RAISE EXCEPTION 'una evidencia ya subida no cambia su archivo' USING ERRCODE = 'restrict_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;

DO $$
BEGIN
  EXECUTE 'DROP TRIGGER IF EXISTS t10_sellar_autoria ON public.evidencias_animal';
  EXECUTE 'CREATE TRIGGER t10_sellar_autoria BEFORE INSERT OR UPDATE ON public.evidencias_animal
           FOR EACH ROW EXECUTE FUNCTION public.sellar_autoria()';
  IF NOT EXISTS (SELECT 1 FROM pg_trigger g WHERE g.tgrelid = 'public.evidencias_animal'::regclass
                 AND NOT g.tgisinternal AND g.tgfoid = 'public.actualizar_timestamps()'::regprocedure) THEN
    EXECUTE 'CREATE TRIGGER t20_timestamps BEFORE UPDATE ON public.evidencias_animal
             FOR EACH ROW EXECUTE FUNCTION public.actualizar_timestamps()';
  END IF;
  EXECUTE 'DROP TRIGGER IF EXISTS t30_bloquear_delete ON public.evidencias_animal';
  EXECUTE 'CREATE TRIGGER t30_bloquear_delete BEFORE DELETE ON public.evidencias_animal
           FOR EACH ROW EXECUTE FUNCTION public.bloquear_delete()';
  EXECUTE 'DROP TRIGGER IF EXISTS t50_evidencias_reglas ON public.evidencias_animal';
  EXECUTE 'CREATE TRIGGER t50_evidencias_reglas BEFORE INSERT OR UPDATE ON public.evidencias_animal
           FOR EACH ROW EXECUTE FUNCTION public.evidencias_animal_reglas()';
  EXECUTE 'DROP TRIGGER IF EXISTS t90_auditar ON public.evidencias_animal';
  EXECUTE 'CREATE TRIGGER t90_auditar AFTER INSERT OR UPDATE ON public.evidencias_animal
           FOR EACH ROW EXECUTE FUNCTION public.auditar_cambio()';
  EXECUTE 'ALTER TABLE public.evidencias_animal ENABLE ROW LEVEL SECURITY';
END $$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON public.evidencias_animal FROM anon';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN RETURN; END IF;
  EXECUTE 'REVOKE DELETE, TRUNCATE ON public.evidencias_animal FROM authenticated';
  EXECUTE 'DROP POLICY IF EXISTS p05_evidencias_select ON public.evidencias_animal';
  EXECUTE 'CREATE POLICY p05_evidencias_select ON public.evidencias_animal FOR SELECT TO authenticated
           USING (public.es_miembro_finca(finca_id))';
  EXECUTE 'DROP POLICY IF EXISTS p05_evidencias_insert ON public.evidencias_animal';
  EXECUTE 'CREATE POLICY p05_evidencias_insert ON public.evidencias_animal FOR INSERT TO authenticated
           WITH CHECK (public.es_miembro_finca(finca_id))';
  EXECUTE 'DROP POLICY IF EXISTS p05_evidencias_update ON public.evidencias_animal';
  EXECUTE 'CREATE POLICY p05_evidencias_update ON public.evidencias_animal FOR UPDATE TO authenticated
           USING (public.es_miembro_finca(finca_id)) WITH CHECK (public.es_miembro_finca(finca_id))';
END $$;
