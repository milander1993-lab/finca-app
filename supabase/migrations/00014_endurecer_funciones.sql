-- ============================================================================
-- 00014_endurecer_funciones.sql — Seguridad (aviso del asesor de Supabase, 1-oct-2026).
-- Supabase da EXECUTE a anon/authenticated por defecto. Aquí: ninguna función de
-- public la ejecuta un anónimo; las de trigger no las ejecuta nadie por API; solo
-- las funciones que la app usa quedan para usuarios con sesión (y verifican
-- membresía por dentro). Idempotente.
-- ============================================================================
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT p.oid::regprocedure AS fn, pg_get_function_result(p.oid) AS res
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND p.prokind = 'f'
              AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', r.fn);
    IF r.res = 'trigger' THEN
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM authenticated', r.fn);
    END IF;
  END LOOP;
END $$;
GRANT EXECUTE ON FUNCTION public.es_miembro_finca(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.qr_revisar_operacion(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.crear_finca_inicial(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mover_animal_lote(uuid,uuid,uuid,timestamptz,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.calcular_demanda_ms_lote(uuid,uuid,timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ocupacion_max_horas() TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon;
