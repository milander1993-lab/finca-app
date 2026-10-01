import 'package:flutter/material.dart';

/// Colores funcionales aprobados (D-020). No es el diseño visual definitivo (34.14).
class ColoresArea {
  static const agroecologia = Color(0xFF2E7D32); // verde
  static const ganaderia = Color(0xFFC62828); // rojo
  static const infraestructura = Color(0xFFF9A825); // amarillo
  /// Áreas sin color aprobado: neutro (no se inventa un color de área).
  static const general = Color(0xFF455A64);
}

ThemeData temaApp() => ThemeData(
      useMaterial3: true,
      colorSchemeSeed: ColoresArea.agroecologia,
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    );
