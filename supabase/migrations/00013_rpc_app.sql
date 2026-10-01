-- ============================================================================
-- 00013_rpc_app.sql — Funciones que usa la app (ADITIVA e idempotente; requiere 00004).
-- 1) crear_finca_inicial(nombre): el usuario recién registrado crea SU finca y queda
--    como miembro, sin SQL manual. Solo si aún no pertenece a ninguna finca.
-- 2) mover_animal_lote(...): cierra la pertenencia abierta y abre la nueva en UNA
--    transacción (nunca queda un animal sin historia ni en dos lotes).
-- ============================================================================
DO $$ BEGIN
  IF to_regclass('public.animal_lote') IS NULL THEN RAISE EXCEPTION '00013 requiere 00004.'; END IF;
END $$;

CREATE OR REPLACE FUNCTION public.crear_finca_inicial(p_nombre text)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id  uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'debe iniciar sesión' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF btrim(coalesce(p_nombre, '')) = '' THEN
    RAISE EXCEPTION 'el nombre de la finca es obligatorio' USING ERRCODE = 'check_violation';
  END IF;
  IF EXISTS (SELECT 1 FROM public.finca_miembros WHERE user_id = v_uid AND activo AND NOT is_deleted) THEN
    RAISE EXCEPTION 'el usuario ya pertenece a una finca' USING ERRCODE = 'check_violation';
  END IF;
  INSERT INTO public.fincas (nombre) VALUES (btrim(p_nombre)) RETURNING id INTO v_id;
  INSERT INTO public.finca_miembros (finca_id, user_id) VALUES (v_id, v_uid);
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION public.mover_animal_lote(
  p_finca uuid, p_animal uuid, p_lote uuid, p_fecha timestamptz, p_motivo text)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_abierta public.animal_lote%ROWTYPE;
  v_id uuid;
BEGIN
  IF NOT public.es_miembro_finca(p_finca) THEN
    RAISE EXCEPTION 'Sin acceso a la finca indicada' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF btrim(coalesce(p_motivo, '')) = '' THEN
    RAISE EXCEPTION 'mover de lote exige motivo' USING ERRCODE = 'check_violation';
  END IF;
  PERFORM 1 FROM public.animales WHERE id = p_animal AND finca_id = p_finca AND NOT is_deleted FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'el animal no existe en la finca' USING ERRCODE = 'integrity_constraint_violation';
  END IF;
  SELECT * INTO v_abierta FROM public.animal_lote
   WHERE animal_id = p_animal AND fecha_salida IS NULL AND NOT is_deleted FOR UPDATE;
  IF FOUND THEN
    IF v_abierta.lote_id = p_lote THEN
      RAISE EXCEPTION 'el animal ya está en ese lote' USING ERRCODE = 'check_violation';
    END IF;
    UPDATE public.animal_lote SET fecha_salida = p_fecha, motivo_salida = btrim(p_motivo) WHERE id = v_abierta.id;
  END IF;
  INSERT INTO public.animal_lote (finca_id, animal_id, lote_id, fecha_ingreso, motivo_ingreso)
  VALUES (p_finca, p_animal, p_lote, p_fecha, btrim(p_motivo))
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.crear_finca_inicial(text) FROM anon, public';
    EXECUTE 'REVOKE ALL ON FUNCTION public.mover_animal_lote(uuid,uuid,uuid,timestamptz,text) FROM anon, public';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.crear_finca_inicial(text) TO authenticated';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.mover_animal_lote(uuid,uuid,uuid,timestamptz,text) TO authenticated';
  END IF;
END $$;
