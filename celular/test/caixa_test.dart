/// O valor digitado no caixa vira centavos sem passar por `double`.
///
/// Fundo e sangria são digitados à mão, no balcão, e um centavo perdido aqui é
/// uma gaveta que não bate no fim do dia.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tronvix_facil/formato.dart';

void main() {
  test('entende o valor como se fala', () {
    expect(paraCentavos('150'), 15000);
    expect(paraCentavos('150,5'), 15050);
    expect(paraCentavos('150,00'), 15000);
    expect(paraCentavos('R\$ 1.234,56'), 123456);
    expect(paraCentavos('27.90'), 2790);
    expect(paraCentavos('1.234'), 123400);
    expect(paraCentavos(',50'), 50);
  });

  test('não arredonda: 0,29 é 29 centavos, não 28', () {
    // 0.29 * 100 em double dá 28.999999999999996.
    expect(paraCentavos('0,29'), 29);
    expect(paraCentavos('1,13'), 113);
  });

  test('recusa o que não é valor', () {
    expect(paraCentavos(''), isNull);
    expect(paraCentavos('abc'), isNull);
    expect(paraCentavos('10,999'), isNull);
    expect(paraCentavos('1,2,3'), isNull);
    expect(paraCentavos('-10'), isNull);
  });
}
