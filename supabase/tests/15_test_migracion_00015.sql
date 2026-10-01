\pset pager off
SET ROLE authenticated; SET request.jwt.claim.sub='11111111-1111-1111-1111-111111111111';
SELECT 'T respaldo trae todas las tablas y solo la finca propia' t,
  (r->>'formato')='finca-respaldo.v1'
  AND jsonb_array_length(r->'tablas'->'animales') = (SELECT count(*) FROM animales WHERE finca_id='aaaaaaaa-0000-0000-0000-000000000001')
  AND jsonb_array_length(r->'tablas'->'fincas')=1
  AND (r->'tablas') ? 'aforo_muestras' AND (r->'tablas') ? 'auditoria'
  AND NOT (r::text LIKE '%X-001%') ok
FROM (SELECT exportar_finca('aaaaaaaa-0000-0000-0000-000000000001') r) s;
SELECT 'T incluye anulados (historia)' t, (SELECT count(*) FROM jsonb_array_elements(exportar_finca('aaaaaaaa-0000-0000-0000-000000000001')->'tablas'->'pesajes') e WHERE (e->>'is_deleted')::bool) >= 1 ok;
DO $$ BEGIN PERFORM exportar_finca('aaaaaaaa-0000-0000-0000-000000000002'); RAISE NOTICE 'FALLA: exportó finca ajena'; EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'OK no exporta finca ajena'; END $$;
RESET ROLE;
