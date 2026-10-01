-- ============================================================================
-- 00003_mapa_geometrias.sql — Iteración 1, submódulo B (mapa)
-- ADITIVA e idempotente. Requiere 00002.
--
-- Principios:
--  * No se inventa ninguna geometría: sin datos reales, el mapa dice "sin datos".
--  * Una geometría guardada siempre es válida y está en SRID 4326 (WGS84).
--  * Área y centroide se CALCULAN a partir de la geometría (naturaleza: calculado);
--    no se almacenan como si fueran medidos (DA-025).
--  * La precisión real de la geometría (¿trazada en mapa o medida con GPS?) es un
--    pendiente 34.8: aquí se guarda solo la naturaleza declarada por quien la registra.
-- ============================================================================

DO $$ BEGIN
  IF to_regclass('public.unidades_espaciales') IS NULL
     OR to_regclass('public.finca_miembros') IS NULL THEN
    RAISE EXCEPTION '00003 requiere 00001 y 00002.';
  END IF;
END $$;

-- Naturaleza declarada de la geometría (nula = pendiente de verificar)
ALTER TABLE public.unidades_espaciales
  ADD COLUMN IF NOT EXISTS geometria_naturaleza public.naturaleza_dato;

-- Geometría siempre válida y en 4326
CREATE OR REPLACE FUNCTION public.geometria_valida()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, extensions, pg_temp
AS $$
BEGIN
  IF NEW.geometria IS NULL THEN
    RETURN NEW;                       -- sin geometría = "sin datos", permitido
  END IF;
  IF ST_SRID(NEW.geometria) <> 4326 THEN
    RAISE EXCEPTION 'la geometría debe estar en SRID 4326 (recibido %)', ST_SRID(NEW.geometria)
      USING ERRCODE = 'check_violation';
  END IF;
  IF ST_IsEmpty(NEW.geometria) OR NOT ST_IsValid(NEW.geometria) THEN
    RAISE EXCEPTION 'geometría inválida: %', ST_IsValidReason(NEW.geometria)
      USING ERRCODE = 'check_violation';
  END IF;
  IF NOT (ST_XMin(NEW.geometria) >= -180 AND ST_XMax(NEW.geometria) <= 180
      AND ST_YMin(NEW.geometria) >= -90  AND ST_YMax(NEW.geometria) <= 90) THEN
    RAISE EXCEPTION 'coordenadas fuera de rango (lon/lat)' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.geometria_naturaleza IS NULL THEN
    RAISE EXCEPTION 'declare la naturaleza de la geometría (medido, estimado, ...)'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS t40_geometria_valida ON public.unidades_espaciales;
CREATE TRIGGER t40_geometria_valida
  BEFORE INSERT OR UPDATE OF geometria, geometria_naturaleza ON public.unidades_espaciales
  FOR EACH ROW EXECUTE FUNCTION public.geometria_valida();

-- Vista para el cliente. security_invoker => se aplica RLS de quien consulta.
-- Las geometrías se exponen como GeoJSON (texto) y con área calculada en m².
CREATE OR REPLACE VIEW public.v_unidades_mapa
WITH (security_invoker = true) AS
SELECT
  u.id,
  u.finca_id,
  u.parent_id,
  u.tipo,
  u.nombre,
  u.es_temporal,
  u.estado,
  u.geometria_naturaleza,
  CASE WHEN u.geometria IS NULL THEN NULL ELSE extensions.ST_AsGeoJSON(u.geometria, 7) END AS geometria_geojson,
  CASE WHEN u.geometria IS NULL THEN NULL
       ELSE round(extensions.ST_Area(u.geometria::extensions.geography)::numeric, 1) END              AS area_m2_calculada,
  u.updated_at
FROM public.unidades_espaciales u
WHERE NOT u.is_deleted;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON public.v_unidades_mapa FROM anon';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    EXECUTE 'REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.v_unidades_mapa FROM authenticated';
    EXECUTE 'GRANT SELECT ON public.v_unidades_mapa TO authenticated';
  END IF;
END $$;
