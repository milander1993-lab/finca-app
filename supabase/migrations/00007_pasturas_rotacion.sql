-- ============================================================================
-- 00007_pasturas_rotacion.sql — Pasturas: potreros, divisiones, ocupación y aforo
-- ADITIVA e idempotente. Requiere 00002 y 00004 (lotes) ; 00006 (guías) opcional.
--
-- Reglas ya aprobadas que implementa (NO son datos de la finca, son reglas):
--  * D-012 / DA-047: máximo 6 potreros principales; las divisiones temporales
--    (cerca eléctrica) NO se vuelven potreros permanentes.
--  * Las divisiones se nombran libremente (A1, A2, ...): el sistema solo exige
--    que el nombre sea único en la finca y que la división cuelgue de un potrero.
--  * Máximo 2 días de ocupación por área pastoreada: superarlo genera ALERTA, sin
--    inventar la causa (D-012).
--  * No existe la relación permanente animal = potrero: se ocupa con un LOTE.
--  * Ocupación sin solapamientos incoherentes (6.2).
--  * Superficie: cuántas hectáreas se destinan a cada área; vacío = "sin datos".
--  * Aforo: %MS = materia seca / materia fresca × 100; si falta un dato
--    indispensable → NO CALCULABLE (6.3). El método de aforo (34.6) está pendiente:
--    cada aforo puede referenciar una guía versionada (00006) cuando exista.
--
-- Convención de `unidades_espaciales.tipo` usada aquí: 'potrero' y 'division'.
-- Si tu base real usa otros valores, el diagnóstico lo mostrará y se ajusta.
-- ============================================================================

DO $$ BEGIN
  IF to_regclass('public.lotes_ganaderos') IS NULL OR to_regclass('public.animal_lote') IS NULL THEN
    RAISE EXCEPTION '00007 requiere 00004 (lotes).';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 1. Superficie por unidad y por destino
-- ---------------------------------------------------------------------------
ALTER TABLE public.unidades_espaciales
  ADD COLUMN IF NOT EXISTS superficie_ha numeric(12,4) CHECK (superficie_ha IS NULL OR superficie_ha > 0),
  ADD COLUMN IF NOT EXISTS superficie_naturaleza public.naturaleza_dato;

-- Hectáreas destinadas a cada área. El destino es de texto libre (lo define el
-- usuario: ganadería, vivero, conservación, lo que registre); no se siembra ningún valor.
CREATE TABLE IF NOT EXISTS public.destinos_superficie (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id     uuid NOT NULL REFERENCES public.fincas(id),
  destino      text NOT NULL CHECK (btrim(destino) <> ''),
  superficie_ha numeric(12,4) NOT NULL CHECK (superficie_ha > 0),
  naturaleza   public.naturaleza_dato NOT NULL,        -- sin valor por defecto: se declara
  observaciones text,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  created_by   uuid REFERENCES auth.users(id),
  updated_by   uuid REFERENCES auth.users(id),
  version      integer NOT NULL DEFAULT 1,
  is_deleted   boolean NOT NULL DEFAULT false
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_destinos_finca_destino
  ON public.destinos_superficie (finca_id, lower(btrim(destino))) WHERE NOT is_deleted;

-- ---------------------------------------------------------------------------
-- 2. Reglas de potreros y divisiones
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.potreros_reglas()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_padre_tipo text;
  v_padre_finca uuid;
  v_n integer;
BEGIN
  IF NEW.tipo NOT IN ('potrero','division') THEN
    RETURN NEW;                          -- otros tipos de unidad no se tocan
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.tipo IS DISTINCT FROM OLD.tipo AND OLD.tipo IN ('potrero','division') THEN
      RAISE EXCEPTION 'un potrero no se convierte en división ni al revés (DA-047)' USING ERRCODE = 'restrict_violation';
    END IF;
    IF OLD.tipo = 'division' AND NEW.es_temporal IS DISTINCT FROM OLD.es_temporal THEN
      RAISE EXCEPTION 'una división temporal no se vuelve permanente (DA-047)' USING ERRCODE = 'restrict_violation';
    END IF;
  END IF;

  IF NEW.tipo = 'division' THEN
    IF NEW.es_temporal IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'las divisiones son temporales (DA-047)' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.parent_id IS NULL THEN
      RAISE EXCEPTION 'una división debe pertenecer a un potrero' USING ERRCODE = 'check_violation';
    END IF;
    SELECT tipo, finca_id INTO v_padre_tipo, v_padre_finca FROM public.unidades_espaciales WHERE id = NEW.parent_id;
    IF v_padre_tipo IS DISTINCT FROM 'potrero' OR v_padre_finca IS DISTINCT FROM NEW.finca_id THEN
      RAISE EXCEPTION 'el padre de una división debe ser un potrero de la misma finca' USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  IF NEW.tipo = 'potrero' THEN
    IF NEW.parent_id IS NOT NULL THEN
      RAISE EXCEPTION 'un potrero principal no tiene padre' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.es_temporal IS TRUE THEN
      RAISE EXCEPTION 'un potrero principal no es temporal' USING ERRCODE = 'check_violation';
    END IF;
    IF NOT NEW.is_deleted THEN
      PERFORM pg_advisory_xact_lock(hashtext('potreros:' || NEW.finca_id::text));
      SELECT count(*) INTO v_n FROM public.unidades_espaciales
       WHERE finca_id = NEW.finca_id AND tipo = 'potrero' AND NOT is_deleted AND id <> NEW.id;
      IF v_n >= 6 THEN
        RAISE EXCEPTION 'máximo 6 potreros principales por finca (D-012)' USING ERRCODE = 'check_violation';
      END IF;
    END IF;
  END IF;

  IF NOT NEW.is_deleted AND NEW.nombre IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM public.unidades_espaciales u
                WHERE u.finca_id = NEW.finca_id AND u.tipo IN ('potrero','division') AND NOT u.is_deleted
                  AND u.id <> NEW.id AND lower(btrim(u.nombre)) = lower(btrim(NEW.nombre))) THEN
      RAISE EXCEPTION 'ya existe un potrero o división llamado "%"', NEW.nombre USING ERRCODE = 'unique_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS t45_potreros_reglas ON public.unidades_espaciales;
CREATE TRIGGER t45_potreros_reglas BEFORE INSERT OR UPDATE ON public.unidades_espaciales
  FOR EACH ROW EXECUTE FUNCTION public.potreros_reglas();

-- La superficie declarada exige su naturaleza (no hay valor sin saber de dónde viene)
CREATE OR REPLACE FUNCTION public.superficie_naturaleza_exigida()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.superficie_ha IS NOT NULL AND NEW.superficie_naturaleza IS NULL THEN
    RAISE EXCEPTION 'declare la naturaleza de la superficie (medido, estimado, ...)' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS t46_superficie_naturaleza ON public.unidades_espaciales;
CREATE TRIGGER t46_superficie_naturaleza BEFORE INSERT OR UPDATE OF superficie_ha, superficie_naturaleza ON public.unidades_espaciales
  FOR EACH ROW EXECUTE FUNCTION public.superficie_naturaleza_exigida();

-- ---------------------------------------------------------------------------
-- 3. Ocupación de pastoreo (lote ↔ área, con entrada y salida)
-- ---------------------------------------------------------------------------
-- Límite de ocupación en horas: D-012 = 2 días. Función para poder cambiarlo con
-- una migración nueva sin tocar vistas ni datos.
CREATE OR REPLACE FUNCTION public.ocupacion_max_horas() RETURNS integer
LANGUAGE sql IMMUTABLE AS $$ SELECT 48 $$;

CREATE TABLE IF NOT EXISTS public.ocupaciones_pastoreo (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id    uuid NOT NULL REFERENCES public.fincas(id),
  unidad_id   uuid NOT NULL REFERENCES public.unidades_espaciales(id),
  lote_id     uuid NOT NULL REFERENCES public.lotes_ganaderos(id),
  entrada_en  timestamptz NOT NULL,
  salida_en   timestamptz,
  observaciones text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  created_by  uuid REFERENCES auth.users(id),
  updated_by  uuid REFERENCES auth.users(id),
  version     integer NOT NULL DEFAULT 1,
  is_deleted  boolean NOT NULL DEFAULT false,
  CHECK (salida_en IS NULL OR salida_en >= entrada_en)
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_ocupacion_abierta_por_unidad
  ON public.ocupaciones_pastoreo (unidad_id) WHERE salida_en IS NULL AND NOT is_deleted;
CREATE UNIQUE INDEX IF NOT EXISTS ux_ocupacion_abierta_por_lote
  ON public.ocupaciones_pastoreo (lote_id) WHERE salida_en IS NULL AND NOT is_deleted;
CREATE INDEX IF NOT EXISTS ix_ocupacion_unidad ON public.ocupaciones_pastoreo (unidad_id, entrada_en DESC);
CREATE INDEX IF NOT EXISTS ix_ocupacion_lote ON public.ocupaciones_pastoreo (lote_id, entrada_en DESC);

CREATE OR REPLACE FUNCTION public.ocupacion_reglas()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_u public.unidades_espaciales%ROWTYPE;
  v_choque text;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.unidad_id IS DISTINCT FROM OLD.unidad_id OR NEW.lote_id IS DISTINCT FROM OLD.lote_id
       OR NEW.entrada_en IS DISTINCT FROM OLD.entrada_en THEN
      RAISE EXCEPTION 'la ocupación no se reescribe: solo se cierra con la salida (D-010)' USING ERRCODE = 'restrict_violation';
    END IF;
    IF OLD.salida_en IS NOT NULL AND NEW.salida_en IS DISTINCT FROM OLD.salida_en THEN
      RAISE EXCEPTION 'la ocupación ya fue cerrada' USING ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
  END IF;

  SELECT * INTO v_u FROM public.unidades_espaciales WHERE id = NEW.unidad_id AND NOT is_deleted;
  IF NOT FOUND OR v_u.finca_id <> NEW.finca_id OR v_u.tipo NOT IN ('potrero','division') THEN
    RAISE EXCEPTION 'la unidad debe ser un potrero o división de la finca' USING ERRCODE = 'integrity_constraint_violation';
  END IF;
  IF (SELECT finca_id FROM public.lotes_ganaderos WHERE id = NEW.lote_id AND NOT is_deleted) IS DISTINCT FROM NEW.finca_id THEN
    RAISE EXCEPTION 'el lote debe pertenecer a la finca' USING ERRCODE = 'integrity_constraint_violation';
  END IF;
  IF NEW.entrada_en > now() + interval '10 minutes' THEN
    RAISE EXCEPTION 'entrada_en en el futuro' USING ERRCODE = 'check_violation';
  END IF;

  -- sin solapamientos incoherentes: no se ocupa a la vez un potrero y una de sus divisiones
  IF NEW.salida_en IS NULL THEN
    SELECT u.nombre INTO v_choque
      FROM public.ocupaciones_pastoreo o
      JOIN public.unidades_espaciales u ON u.id = o.unidad_id
     WHERE o.salida_en IS NULL AND NOT o.is_deleted
       AND (o.unidad_id = v_u.parent_id OR u.parent_id = NEW.unidad_id)
     LIMIT 1;
    IF FOUND THEN
      RAISE EXCEPTION 'solapamiento: "%" ya está ocupado y contiene o pertenece a esta unidad', v_choque
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS t50_ocupacion_reglas ON public.ocupaciones_pastoreo;
CREATE TRIGGER t50_ocupacion_reglas BEFORE INSERT OR UPDATE ON public.ocupaciones_pastoreo
  FOR EACH ROW EXECUTE FUNCTION public.ocupacion_reglas();

-- Alerta: ocupación que supera el límite. NO se inventa la causa (D-012).
CREATE OR REPLACE VIEW public.v_alertas_ocupacion
WITH (security_invoker = true) AS
SELECT
  o.id AS ocupacion_id, o.finca_id, o.unidad_id, u.nombre AS unidad_nombre,
  o.lote_id, l.nombre AS lote_nombre, o.entrada_en, o.salida_en,
  (o.salida_en IS NULL) AS abierta,
  round((extract(epoch FROM (coalesce(o.salida_en, now()) - o.entrada_en)) / 3600.0)::numeric, 1) AS horas_ocupadas,
  public.ocupacion_max_horas() AS limite_horas,
  (extract(epoch FROM (coalesce(o.salida_en, now()) - o.entrada_en)) / 3600.0 > public.ocupacion_max_horas()) AS excede_limite,
  CASE WHEN extract(epoch FROM (coalesce(o.salida_en, now()) - o.entrada_en)) / 3600.0 > public.ocupacion_max_horas()
       THEN 'Ocupación superior al límite de ' || (public.ocupacion_max_horas() / 24) || ' días (causa por determinar)'
  END AS mensaje
FROM public.ocupaciones_pastoreo o
JOIN public.unidades_espaciales u ON u.id = o.unidad_id
JOIN public.lotes_ganaderos l ON l.id = o.lote_id
WHERE NOT o.is_deleted;

-- ---------------------------------------------------------------------------
-- 4. Aforos (estructura; el método está pendiente, 34.6)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.aforos (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id        uuid NOT NULL REFERENCES public.fincas(id),
  unidad_id       uuid NOT NULL REFERENCES public.unidades_espaciales(id),
  fecha_aforo     timestamptz NOT NULL,
  area_muestra_m2 numeric(10,3) CHECK (area_muestra_m2 IS NULL OR area_muestra_m2 > 0),
  materia_fresca_g numeric(12,3) CHECK (materia_fresca_g IS NULL OR materia_fresca_g > 0),
  materia_seca_g  numeric(12,3) CHECK (materia_seca_g IS NULL OR materia_seca_g > 0),
  metodo          text,
  guia_version_id uuid REFERENCES public.guia_versiones(id),   -- regla de oro: cómo se obtuvo
  naturaleza      public.naturaleza_dato NOT NULL,
  responsable_id  uuid REFERENCES auth.users(id),
  observaciones   text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  created_by      uuid REFERENCES auth.users(id),
  updated_by      uuid REFERENCES auth.users(id),
  version         integer NOT NULL DEFAULT 1,
  is_deleted      boolean NOT NULL DEFAULT false,
  CHECK (materia_seca_g IS NULL OR materia_fresca_g IS NULL OR materia_seca_g <= materia_fresca_g)
);
CREATE INDEX IF NOT EXISTS ix_aforos_unidad ON public.aforos (unidad_id, fecha_aforo DESC) WHERE NOT is_deleted;

CREATE OR REPLACE FUNCTION public.aforos_reglas()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF (SELECT finca_id FROM public.unidades_espaciales WHERE id = NEW.unidad_id) IS DISTINCT FROM NEW.finca_id THEN
    RAISE EXCEPTION 'la unidad no pertenece a la finca' USING ERRCODE = 'integrity_constraint_violation';
  END IF;
  IF NEW.fecha_aforo > now() + interval '10 minutes' THEN
    RAISE EXCEPTION 'fecha_aforo en el futuro' USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'UPDATE' AND (NEW.unidad_id IS DISTINCT FROM OLD.unidad_id OR NEW.fecha_aforo IS DISTINCT FROM OLD.fecha_aforo) THEN
    RAISE EXCEPTION 'un aforo no se reescribe: anule y registre de nuevo' USING ERRCODE = 'restrict_violation';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS t50_aforos_reglas ON public.aforos;
CREATE TRIGGER t50_aforos_reglas BEFORE INSERT OR UPDATE ON public.aforos
  FOR EACH ROW EXECUTE FUNCTION public.aforos_reglas();

-- %MS y producción de MS: CALCULADOS; sin dato indispensable => NULL + 'no_calculable'
CREATE OR REPLACE VIEW public.v_aforos_calculo
WITH (security_invoker = true) AS
SELECT
  a.id, a.finca_id, a.unidad_id, a.fecha_aforo, a.naturaleza, a.guia_version_id,
  CASE WHEN a.materia_seca_g IS NOT NULL AND a.materia_fresca_g IS NOT NULL
       THEN round((a.materia_seca_g / a.materia_fresca_g * 100)::numeric, 2) END AS ms_pct_calculado,
  CASE WHEN a.materia_seca_g IS NOT NULL AND a.area_muestra_m2 IS NOT NULL
       THEN round((a.materia_seca_g / a.area_muestra_m2)::numeric, 2) END AS ms_g_por_m2_calculado,
  CASE WHEN a.materia_seca_g IS NULL OR a.materia_fresca_g IS NULL THEN 'no_calculable' ELSE 'calculado' END AS estado_ms_pct
FROM public.aforos a
WHERE NOT a.is_deleted;

-- ---------------------------------------------------------------------------
-- 5. Triggers comunes, RLS y privilegios
-- ---------------------------------------------------------------------------
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['destinos_superficie','ocupaciones_pastoreo','aforos'] LOOP
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

DO $$
DECLARE t text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON public.destinos_superficie, public.ocupaciones_pastoreo, public.aforos,
                           public.v_alertas_ocupacion, public.v_aforos_calculo FROM anon';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN RETURN; END IF;
  EXECUTE 'REVOKE DELETE, TRUNCATE ON public.destinos_superficie, public.ocupaciones_pastoreo, public.aforos FROM authenticated';
  EXECUTE 'REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.v_alertas_ocupacion, public.v_aforos_calculo FROM authenticated';
  EXECUTE 'GRANT SELECT ON public.v_alertas_ocupacion, public.v_aforos_calculo TO authenticated';
  FOREACH t IN ARRAY ARRAY['destinos_superficie','ocupaciones_pastoreo','aforos'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS p07_%s_select ON public.%I', t, t);
    EXECUTE format('CREATE POLICY p07_%s_select ON public.%I FOR SELECT TO authenticated
                    USING (public.es_miembro_finca(finca_id))', t, t);
    EXECUTE format('DROP POLICY IF EXISTS p07_%s_insert ON public.%I', t, t);
    EXECUTE format('CREATE POLICY p07_%s_insert ON public.%I FOR INSERT TO authenticated
                    WITH CHECK (public.es_miembro_finca(finca_id))', t, t);
    EXECUTE format('DROP POLICY IF EXISTS p07_%s_update ON public.%I', t, t);
    EXECUTE format('CREATE POLICY p07_%s_update ON public.%I FOR UPDATE TO authenticated
                    USING (public.es_miembro_finca(finca_id)) WITH CHECK (public.es_miembro_finca(finca_id))', t, t);
  END LOOP;
END $$;
