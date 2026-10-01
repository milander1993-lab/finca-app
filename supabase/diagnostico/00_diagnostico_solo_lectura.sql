-- DIAGNÓSTICO SOLO LECTURA — pégalo en el SQL Editor de tu Supabase (proyecto de PRUEBA primero).
-- No modifica nada. Copia los resultados de las 6 consultas y pásamelos.

-- 1. ¿Qué tablas existen en public? (responde: lotes_ganaderos, personas, infraestructuras, especies)
select table_name from information_schema.tables where table_schema='public' order by 1;

-- 2. Columnas de las tablas clave (¿tienen created_by, version, is_deleted, finca_id?)
select table_name, column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema='public' and table_name in ('fincas','unidades_espaciales','animales','codigos_qr','historial_qr','auditoria','lotes_ganaderos')
order by table_name, ordinal_position;

-- 3. ¿Qué valores reales usa categoria? (para restringirla sin romper nada)
select categoria, count(*) from public.animales group by 1 order by 2 desc;

-- 4. ¿Hay numero_interno duplicados? (00002 se detiene si los hay)
select finca_id, numero_interno, count(*) from public.animales group by 1,2 having count(*)>1;

-- 5. ¿Qué triggers y políticas RLS existen ya? (00002 suma políticas; hay que evitar que ensanchen el acceso)
select event_object_table, trigger_name from information_schema.triggers where trigger_schema='public' order by 1,2;
select tablename, policyname, cmd, roles, qual from pg_policies where schemaname='public' order by 1,2;

-- 6. ¿Qué valores reales tienen estado y tipo? (para validar máquinas de estados y colores del mapa)
select 'qr' as tabla, estado, count(*) from public.codigos_qr group by 2
union all select 'animales', estado, count(*) from public.animales group by 2
union all select 'unidades:'||tipo, estado, count(*) from public.unidades_espaciales group by tipo, estado
order by 1,2;
