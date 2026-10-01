#!/bin/bash
# Corre 00..08 desde cero en la BD de prueba finca_test (Postgres local, SOLO PRUEBA)
P="psql -h /var/run/postgresql -p 54329 -U postgres -v ON_ERROR_STOP=0 -q"
cd "$(dirname "$0")"
dropdb -h /var/run/postgresql -p 54329 -U postgres --if-exists finca_test
createdb -h /var/run/postgresql -p 54329 -U postgres finca_test
$P -d finca_test -f 00_stub_auth_SOLO_PRUEBA.sql >/dev/null 2>&1
$P -d finca_test -f ../migrations/00001_base.sql 2>&1 | grep -i error && echo "ERROR en 00001"
for n in 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
  $P -d finca_test -f ../migrations/$(printf '%05d' $n)_*.sql 2>&1 | grep -i "error" && echo "ERROR en migración 0000$n"
  $P -d finca_test -f $(printf '%02d' $n)_test_migracion_$(printf '%05d' $n).sql 2>&1
done
