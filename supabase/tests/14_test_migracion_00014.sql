\pset pager off
SELECT 'T anon no ejecuta funciones de public' t, NOT has_function_privilege('anon','public.es_miembro_finca(uuid)','EXECUTE') AND NOT has_function_privilege('authenticated','public.auditar_cambio()','EXECUTE') AND has_function_privilege('authenticated','public.crear_finca_inicial(text)','EXECUTE') ok;
