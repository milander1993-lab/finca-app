# Estado (1-oct-2026)
- Base de datos REAL: Supabase "finca-hato-claros" (ref zyqwguollzwejpjvtbll). Migraciones aplicadas y verificadas (prueba de humo 10/10).
- App Flutter: código completo en lib/ conectado a ese proyecto. NO compilado en el entorno de Claude (red sin acceso a Flutter).
- Para compilar y publicar automáticamente: conectar GitHub → el flujo .github/workflows/web.yml construye la PWA (GitHub Pages, gratis) y el APK.
- Alternativa manual en un PC con Flutter: `flutter create . --platforms=web,android --project-name finca_app` y luego `flutter run -d chrome`.
- Pendiente: offline (Drift + PowerSync), evidencias a Drive, respaldo periódico.
