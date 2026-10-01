\pset pager off
SET ROLE authenticated; SET request.jwt.claim.sub='11111111-1111-1111-1111-111111111111';
SELECT 'T sin geometrías: vista vacía' t, count(*)=0 ok FROM v_unidades_mapa;
INSERT INTO unidades_espaciales(id,finca_id,tipo,nombre) VALUES ('cccccccc-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','potrero','P-sin-geo');
SELECT 'T unidad sin geometría => geojson NULL (sin datos)' t, geometria_geojson IS NULL AND area_m2_calculada IS NULL ok FROM v_unidades_mapa;
DO $$ BEGIN UPDATE unidades_espaciales SET geometria=ST_GeomFromText('POLYGON((-75.0 1.0,-75.0 1.001,-74.999 1.001,-74.999 1.0,-75.0 1.0))',4326) WHERE nombre='P-sin-geo'; RAISE NOTICE 'FALLA: aceptó sin naturaleza'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK sin naturaleza rechazado'; END $$;
UPDATE unidades_espaciales SET geometria_naturaleza='estimado', geometria=ST_GeomFromText('POLYGON((-75.0 1.0,-75.0 1.001,-74.999 1.001,-74.999 1.0,-75.0 1.0))',4326) WHERE nombre='P-sin-geo';
SELECT 'T geometría válida: área ~12 mil m2 y geojson' t, area_m2_calculada BETWEEN 11000 AND 13000 AND geometria_geojson LIKE '{"type":"Polygon"%' ok FROM v_unidades_mapa;
DO $$ BEGIN UPDATE unidades_espaciales SET geometria=ST_GeomFromText('POLYGON((0 0,1 1,1 0,0 1,0 0))',4326) WHERE nombre='P-sin-geo'; RAISE NOTICE 'FALLA: moño aceptado'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK polígono inválido rechazado'; END $$;
DO $$ BEGIN UPDATE unidades_espaciales SET geometria=ST_SetSRID(ST_GeomFromText('POLYGON((0 0,0 1,1 1,1 0,0 0))'),3116) WHERE nombre='P-sin-geo'; RAISE NOTICE 'FALLA: srid'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK SRID distinto rechazado'; END $$;
RESET ROLE; SET ROLE authenticated; SET request.jwt.claim.sub='22222222-2222-2222-2222-222222222222';
SELECT 'T no miembro no ve nada en la vista' t, count(*)=0 ok FROM v_unidades_mapa;
RESET ROLE;
