# Runbook: migraciones (YA APLICADAS el 1-oct-2026 en el proyecto Supabase "finca-hato-claros", ref zyqwguollzwejpjvtbll, región São Paulo)
Las migraciones 00001–00009 y 00011–00015 están aplicadas; 00010 se aplicó dentro de 00006. Esta guía queda para reconstruir el proyecto desde cero si hiciera falta.
Hazlo primero en un PROYECTO DE PRUEBA (Supabase permite crear uno aparte), nunca directo en producción.

1. (Opcional) Ejecuta `supabase/diagnostico/00_diagnostico_solo_lectura.sql` y guarda los resultados (no cambia nada).
2. Crea un respaldo (Database → Backups) antes de continuar.
3. Ejecuta EN ORDEN, cada archivo completo y por separado: 00002, 00003, 00004, 00005, 00006, 00007, 00008, 00009, 00010, 00011, 00012, 00013, 00014, 00015 (carpeta `supabase/migrations`).
   - Si alguna dice "PREAPROBACIÓN REQUERIDA" o falla: detente y pásame el mensaje exacto. No edites nada a mano.
   - Son idempotentes: repetir una no rompe nada.
4. Crea tu finca y tu membresía (con el rol de servicio / SQL Editor):
   insert into public.fincas (nombre) values ('<nombre real>') returning id;
   insert into public.finca_miembros (finca_id, user_id) values ('<id finca>', '<id de tu usuario en Auth>');
   Sin este paso la app no verá nada (RLS por pertenencia a finca).
5. PowerSync: sus reglas de sincronización deben filtrar por `finca_miembros` y NO subir `auditoria` desde el cliente.
6. Las pruebas de `supabase/tests/` son solo para un Postgres local de prueba (incluyen un simulacro de Supabase): NO se ejecutan en tu proyecto real.
