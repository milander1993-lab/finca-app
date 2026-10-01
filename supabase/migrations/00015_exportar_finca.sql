-- ============================================================================
-- 00015_exportar_finca.sql — Respaldo de la finca (3.13; el plan gratuito no
-- respalda solo). Devuelve en un JSON todas las filas de la finca (incluidas las
-- anuladas: la historia no se pierde) para guardarlo en Drive desde la app.
-- Se ejecuta con los permisos del usuario (RLS): solo exporta fincas propias.
-- Idempotente.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.exportar_finca(p_finca uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  t text;
  v jsonb := '{}'::jsonb;
  v_filas jsonb;
  v_tablas text[] := ARRAY['fincas','finca_miembros','unidades_espaciales','destinos_superficie','animales',
    'pesajes','lotes_ganaderos','animal_lote','codigos_qr','historial_qr','qr_operaciones','evidencias_animal',
    'ocupaciones_pastoreo','aforos','aforo_muestras','guias','guia_versiones','criterios_parametros','calculos',
    'ia_interacciones','incidentes_tecnicos','auditoria'];
BEGIN
  IF NOT public.es_miembro_finca(p_finca) THEN
    RAISE EXCEPTION 'Sin acceso a la finca indicada' USING ERRCODE = 'insufficient_privilege';
  END IF;
  FOREACH t IN ARRAY v_tablas LOOP
    IF to_regclass('public.' || t) IS NULL THEN CONTINUE; END IF;
    IF t = 'fincas' THEN
      EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x)), ''[]'') FROM public.%I x WHERE x.id = $1', t)
        INTO v_filas USING p_finca;
    ELSE
      EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x)), ''[]'') FROM public.%I x WHERE x.finca_id = $1', t)
        INTO v_filas USING p_finca;
    END IF;
    v := v || jsonb_build_object(t, v_filas);
  END LOOP;
  RETURN jsonb_build_object('formato', 'finca-respaldo.v1', 'generado_en', now(), 'finca_id', p_finca,
                            'generado_por', auth.uid(), 'tablas', v);
END $$;
REVOKE ALL ON FUNCTION public.exportar_finca(uuid) FROM PUBLIC;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.exportar_finca(uuid) FROM anon';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.exportar_finca(uuid) TO authenticated';
  END IF;
END $$;
