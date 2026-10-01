import 'package:flutter/material.dart';

/// Colores iniciales del proyecto (no es el diseño visual definitivo).
class ColoresArea {
  static const agroecologia = Color(0xFF2E7D32); // verde
  static const ganaderia = Color(0xFFC62828); // rojo
  static const infraestructura = Color(0xFFF9A825); // amarillo
}

ThemeData temaApp() => ThemeData(
      useMaterial3: true,
      colorSchemeSeed: ColoresArea.agroecologia,
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    );
