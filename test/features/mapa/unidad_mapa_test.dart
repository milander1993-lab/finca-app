import 'package:flutter_test/flutter_test.dart';
import 'package:finca_app/features/mapa/domain/unidad_mapa.dart';

void main() {
  const poligono =
      '{"type":"Polygon","coordinates":[[[-75.0,1.0],[-75.0,1.001],[-74.999,1.001],[-74.999,1.0],[-75.0,1.0]]]}';

  test('GeoJSON es [lon,lat] y se convierte a (lat,lon)', () {
    final a = anilloDesdeGeoJson(poligono)!;
    expect(a.first.lat, 1.0);
    expect(a.first.lon, -75.0);
    expect(a.length, 5);
  });
  test('nulo, vacío o ilegible = sin datos, sin lanzar', () {
    expect(anilloDesdeGeoJson(null), isNull);
    expect(anilloDesdeGeoJson(' '), isNull);
    expect(anilloDesdeGeoJson('{no es json'), isNull);
    expect(anilloDesdeGeoJson('{"type":"Point","coordinates":[1,2]}'), isNull);
    expect(anilloDesdeGeoJson('{"type":"Polygon","coordinates":[[[1,2],[3,4]]]}'), isNull);
  });
  test('caja envolvente ignora unidades sin geometría', () {
    final con = UnidadMapa(id: '1', tipo: 'potrero', nombre: 'P', esTemporal: false, anillo: anilloDesdeGeoJson(poligono));
    const sin = UnidadMapa(id: '2', tipo: 'potrero', nombre: 'Q', esTemporal: false);
    expect(cajaDe([sin]), isNull);
    final c = cajaDe([con, sin])!;
    expect(c.sur, 1.0);
    expect(c.norte, 1.001);
    expect(c.oeste, -75.0);
    expect(c.este, -74.999);
  });
  test('fila de la vista sin geometría', () {
    final u = unidadDesdeFila({'id': 'x', 'tipo': 'potrero', 'nombre': null, 'es_temporal': null, 'geometria_geojson': null});
    expect(u.tieneGeometria, isFalse);
    expect(u.areaM2Calculada, isNull);
  });
}
