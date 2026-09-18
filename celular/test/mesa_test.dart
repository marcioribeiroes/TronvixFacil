/// O código da mesa, extraído do que a câmera leu.
///
/// A câmera devolve texto cru, e nem todo texto é uma mesa: a pessoa vai
/// apontar o celular para o QR do Pix da maquininha, para a nota fiscal e para
/// o cartão de visita do restaurante. Nenhum deles pode virar uma mesa.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tronvix_facil/dados/mesa.dart';

void main() {
  group('código lido do QR', () {
    test('extrai da URL completa', () {
      expect(
        Mesas.codigoDe('https://pedido.exemplo.com.br/m/6cxb9enb'),
        '6cxb9enb',
      );
    });

    test('extrai de http e de localhost, que é como se testa', () {
      expect(Mesas.codigoDe('http://localhost:3000/m/dc5q2qjx'), 'dc5q2qjx');
    });

    test('ignora o que vem depois, como parâmetro de campanha', () {
      expect(
        Mesas.codigoDe('https://exemplo.com.br/m/jx9w4fmh?utm_source=qr'),
        'jx9w4fmh',
      );
    });

    test('aceita o código digitado a mão, que é o caso da câmera falhar', () {
      expect(Mesas.codigoDe('6cxb9enb'), '6cxb9enb');
    });

    test('aceita em maiúscula: o teclado do celular capitaliza sozinho', () {
      expect(Mesas.codigoDe('6CXB9ENB'), '6cxb9enb');
    });

    test('tira o espaço que a colagem traz junto', () {
      expect(Mesas.codigoDe('  6cxb9enb  '), '6cxb9enb');
    });

    test('QR de outra coisa não vira mesa', () {
      // Pix copia-e-cola.
      expect(Mesas.codigoDe('00020126580014BR.GOV.BCB.PIX0136abc'), isNull);
      // Um site qualquer.
      expect(Mesas.codigoDe('https://exemplo.com.br/promocao'), isNull);
      // Cartão de visita.
      expect(Mesas.codigoDe('BEGIN:VCARD\nFN:Restaurante'), isNull);
      // Texto solto.
      expect(Mesas.codigoDe('mesa 7'), isNull);
    });

    test('código fora do tamanho não passa', () {
      expect(Mesas.codigoDe('abc'), isNull);
      expect(Mesas.codigoDe('a' * 20), isNull);
    });

    test('nada lido é nada', () {
      expect(Mesas.codigoDe(''), isNull);
      expect(Mesas.codigoDe('   '), isNull);
    });
  });

  group('a mesa em que se está sentado', () {
    const mesa = Mesa(
      codigo: '6cxb9enb',
      rotulo: 'Mesa 3',
      restauranteId: 'aaa',
      restauranteNome: 'Espeto de Prata',
      restauranteSlug: 'espeto-de-prata',
    );

    setUp(MesaAtual.instancia.levantar);

    test('sem escanear, não há mesa', () {
      expect(MesaAtual.instancia.mesa, isNull);
      expect(MesaAtual.instancia.serve('aaa'), isFalse);
    });

    test('sentar guarda a mesa', () {
      MesaAtual.instancia.sentar(mesa);
      expect(MesaAtual.instancia.mesa?.rotulo, 'Mesa 3');
      expect(MesaAtual.instancia.serve('aaa'), isTrue);
    });

    test('o QR de uma loja não serve na outra', () {
      MesaAtual.instancia.sentar(mesa);
      expect(MesaAtual.instancia.serve('bbb'), isFalse);
    });

    test('levantar esquece', () {
      MesaAtual.instancia.sentar(mesa);
      MesaAtual.instancia.levantar();
      expect(MesaAtual.instancia.mesa, isNull);
    });

    test('avisa quem está ouvindo, para a faixa aparecer e sumir', () {
      var avisos = 0;
      void contar() => avisos++;
      MesaAtual.instancia.addListener(contar);

      MesaAtual.instancia.sentar(mesa);
      MesaAtual.instancia.levantar();

      MesaAtual.instancia.removeListener(contar);
      expect(avisos, 2);
    });
  });
}
