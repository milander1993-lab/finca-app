import 'package:flutter_test/flutter_test.dart';
import 'package:finca_app/features/qr/domain/qr_estado.dart';
import 'package:finca_app/features/qr/domain/qr_operacion.dart';

void main() {
  test('transiciones idénticas al servidor', () {
    expect(QrEstado.disponible.puedePasarA(QrEstado.asignado), isTrue);
    expect(QrEstado.disponible.puedePasarA(QrEstado.activo), isFalse);
    expect(QrEstado.asignado.puedePasarA(QrEstado.liberado), isTrue);
    expect(QrEstado.activo.puedePasarA(QrEstado.asignado), isFalse);
    expect(QrEstado.liberado.puedePasarA(QrEstado.asignado), isFalse);
    expect(QrEstado.liberado.puedePasarA(QrEstado.disponible), isTrue);
  });
  test('estado desconocido no se adivina', () {
    expect(QrEstado.tryParse('raro'), isNull);
  });
  test('liberar exige motivo', () {
    const v = QrVista(codigo: 'Q', estado: QrEstado.activo, animalActualId: 'a');
    expect(validarLocal(tipo: QrTipoOperacion.liberar, vista: v).esValida, isFalse);
    expect(validarLocal(tipo: QrTipoOperacion.liberar, vista: v, motivo: ' perdido ').esValida, isTrue);
  });
  test('asignar solo si disponible y con animal', () {
    const d = QrVista(codigo: 'Q', estado: QrEstado.disponible);
    const o = QrVista(codigo: 'Q', estado: QrEstado.asignado, animalActualId: 'a');
    expect(validarLocal(tipo: QrTipoOperacion.asignar, vista: d, animalId: 'x').esValida, isTrue);
    expect(validarLocal(tipo: QrTipoOperacion.asignar, vista: d).esValida, isFalse);
    expect(validarLocal(tipo: QrTipoOperacion.asignar, vista: o, animalId: 'x').esValida, isFalse);
    expect(validarLocal(tipo: QrTipoOperacion.asignar, vista: null, animalId: 'x').esValida, isFalse);
  });
  test('normalizar código', () {
    expect(normalizarCodigo('  ABC\n'), 'ABC');
    expect(normalizarCodigo('   '), isNull);
    expect(normalizarCodigo(null), isNull);
  });
}
