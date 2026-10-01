\pset pager off
SET ROLE authenticated; SET request.jwt.claim.sub='11111111-1111-1111-1111-111111111111';
\set F '''aaaaaaaa-0000-0000-0000-000000000001'''
INSERT INTO ia_interacciones(id,finca_id,funcion,contexto,entrada,salida,incertidumbre,modelo,version_modelo,datos_consultados) VALUES ('88888888-0000-0000-0000-000000000001',:F,'explicar_guia','{"pantalla":"aforo"}','¿cómo corto el metro cuadrado?','respuesta de prueba','alta: sin guía publicada','prueba','0','{"tablas":["guias"]}');
SELECT 'T IA registra modelo, versión, datos consultados, usuario' t, modelo='prueba' AND datos_consultados IS NOT NULL AND created_by='11111111-1111-1111-1111-111111111111' AND estado='registrada' ok FROM ia_interacciones;
DO $$ BEGIN UPDATE ia_interacciones SET salida='otra cosa'; RAISE NOTICE 'FALLA: reescribió salida'; EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'OK la salida de la IA no se reescribe'; END $$;
DO $$ BEGIN UPDATE ia_interacciones SET entrada='x'; RAISE NOTICE 'FALLA: reescribió entrada'; EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'OK la entrada no se reescribe'; END $$;
DO $$ BEGIN UPDATE ia_interacciones SET estado='aceptada'; RAISE NOTICE 'FALLA: aceptó sin acción humana'; EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK aceptar exige acción humana'; END $$;
UPDATE ia_interacciones SET estado='aceptada', accion_humana='revisé y lo aplico a mano';
SELECT 'T acción humana con fecha' t, accion_humana_en IS NOT NULL ok FROM ia_interacciones;
DO $$ BEGIN UPDATE ia_interacciones SET accion_humana='cambio'; RAISE NOTICE 'FALLA: cambió acción'; EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'OK la acción humana no se cambia'; END $$;
INSERT INTO incidentes_tecnicos(id,finca_id,tipo,severidad,titulo,origen) VALUES ('77777777-0000-0000-0000-000000000001',:F,'sincronizacion','alta','Operación QR en conflicto','{"tabla":"qr_operaciones"}');
DO $$ BEGIN UPDATE incidentes_tecnicos SET estado='cerrado'; RAISE NOTICE 'FALLA: cerró sin resolución'; EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK cerrar exige resolución'; END $$;
UPDATE incidentes_tecnicos SET estado='en_analisis';
UPDATE incidentes_tecnicos SET estado='cerrado', resolucion='revisado por el administrador';
SELECT 'T incidente cerrado con fecha' t, estado='cerrado' AND cerrado_en IS NOT NULL ok FROM incidentes_tecnicos;
DO $$ BEGIN UPDATE incidentes_tecnicos SET estado='abierto'; RAISE NOTICE 'FALLA: reabrió'; EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'OK incidente cerrado no se modifica'; END $$;
DO $$ BEGIN INSERT INTO incidentes_tecnicos(finca_id,tipo,titulo) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','inventado','x'); RAISE NOTICE 'FALLA: tipo inválido'; EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK tipo inválido rechazado'; END $$;
DO $$ BEGIN DELETE FROM ia_interacciones; RAISE NOTICE 'FALLA delete'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK delete bloqueado'; END $$;
RESET ROLE; SET ROLE authenticated; SET request.jwt.claim.sub='22222222-2222-2222-2222-222222222222';
SELECT 'T no miembro no ve IA ni incidentes' t, (SELECT count(*) FROM ia_interacciones)=0 AND (SELECT count(*) FROM incidentes_tecnicos)=0 ok;
RESET ROLE;
SELECT 'T auditoría IA e incidentes' t, count(*)>=5 ok FROM auditoria WHERE tabla_afectada IN ('ia_interacciones','incidentes_tecnicos');
