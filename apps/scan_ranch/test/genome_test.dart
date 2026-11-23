import 'package:flutter_test/flutter_test.dart';
import 'package:scan_ranch/model/genome.dart';

void main() {
  test('same barcode, same species', () {
    final a = Genome.fromBarcode('036000291452');
    final b = Genome.fromBarcode(' 0036000291452 ');
    expect(a.speciesName, b.speciesName);
    expect(a.plan, b.plan);
    expect(a.element, b.element);
  });

  test('many barcodes give many species', () {
    final names = {
      for (var i = 0; i < 500; i++)
        Genome.fromBarcode('${400000000000 + i * 9973}').speciesName,
    };
    expect(names.length, greaterThan(300));
  });
}
