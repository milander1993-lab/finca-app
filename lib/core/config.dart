/// Configuración del proyecto Supabase "finca-hato-claros" (creado el 1-oct-2026).
/// La clave publicable es pública por diseño (va en todo cliente web/móvil);
/// la seguridad la dan RLS y las reglas en la base. Nunca poner aquí la clave de servicio.
/// Se pueden sobrescribir al compilar con --dart-define.
class Config {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://zyqwguollzwejpjvtbll.supabase.co');
  static const supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'sb_publishable_HYr0X4CSYjsbc2pFHdKYow_ool1Tkan');
  static bool get estaConfigurada => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
