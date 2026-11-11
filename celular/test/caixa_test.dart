/// O valor digitado no caixa vira centavos sem passar por `double`.
///
/// Fundo e sangria são digitados à mão, no balcão, e um centavo perdido aqui é
/// uma gaveta que não bate no fim do dia.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tronvix_facil/formato.dart';
import 'package:tronvix_facil/modelos/modelos.dart';

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

  group('conta dividida', () {
    test('a parte tem de ser mais que zero e caber no que falta', () {
      expect(erroDaParte(5000, 10000), isNull);
      expect(erroDaParte(10000, 10000), isNull);
      expect(erroDaParte(10001, 10000), isNotNull);
      expect(erroDaParte(0, 10000), isNotNull);
      expect(erroDaParte(null, 10000), isNotNull);
    });

    test('o pagamento soma as partes e diz quanto falta', () {
      Map<String, dynamic> pagamento(List<int> partes) => {
            'id': 'p1',
            'method': 'cash',
            'timing': 'on_delivery',
            'status': 'pending',
            'amount_cents': 10000,
            'payment_receipts': [
              for (final v in partes) {'amount_cents': v},
            ],
          };

      final nada = Pagamento.deMapa(pagamento([]));
      expect(nada.recebidoCentavos, 0);
      expect(nada.faltaCentavos, 10000);

      // Cinquenta e cinquenta: a mesma parte duas vezes.
      final metade = Pagamento.deMapa(pagamento([5000]));
      expect(metade.faltaCentavos, 5000);
      final tudo = Pagamento.deMapa(pagamento([5000, 5000]));
      expect(tudo.faltaCentavos, 0);
    });

    test('sem as partes na consulta, falta o total', () {
      final p = Pagamento.deMapa({
        'id': 'p1',
        'method': 'pix',
        'timing': 'on_delivery',
        'status': 'pending',
        'amount_cents': 2790,
      });
      expect(p.faltaCentavos, 2790);
    });
  });
}
