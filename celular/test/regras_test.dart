/// Os testes verificam as regras que o aplicativo tem de acertar sozinho —
/// dinheiro, janela de promoção, frete grátis, e o espelho da máquina de
/// estados do banco.
///
/// O que não está aqui, de propósito: nada que o banco já garanta. Testar no
/// Dart que um pedido entregue não volta a "em preparo" seria testar a cópia,
/// não a regra. A regra está em `app.order_transition_allowed` e é verificada
/// em `supabase/tests/regras_do_fechamento.sql`. O que este arquivo cobre é a
/// **fidelidade** da cópia.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tronvix_facil/dados/carrinho.dart';
import 'package:tronvix_facil/formato.dart';
import 'package:tronvix_facil/modelos/modelos.dart';

Produto produto({
  int preco = 2500,
  int? promo,
  DateTime? comeca,
  DateTime? termina,
  bool controlaEstoque = false,
  int estoque = 0,
  bool disponivel = true,
}) =>
    Produto(
      id: 'p1',
      restauranteId: 'r1',
      categoriaId: 'c1',
      nome: 'X-Salada',
      precoCentavos: preco,
      disponivel: disponivel,
      destaque: false,
      precoPromocionalCentavos: promo,
      promocaoComecaEm: comeca,
      promocaoTerminaEm: termina,
      controlaEstoque: controlaEstoque,
      quantidadeEmEstoque: estoque,
    );

Restaurante restaurante({int taxa = 700, int? gratisAcima}) => Restaurante(
      id: 'r1',
      slug: 'burger',
      nome: 'Burger House',
      aberto: true,
      taxaDeEntregaCentavos: taxa,
      pedidoMinimoCentavos: 2000,
      minutosDePreparo: 30,
      minutosDeEntrega: 20,
      notaMedia: 4.7,
      quantidadeDeNotas: 12,
      entregaGratisAcimaDeCentavos: gratisAcima,
    );

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  group('dinheiro', () {
    test('centavos viram reais no formato brasileiro', () {
      expect(emReais(0), contains('0,00'));
      expect(emReais(5400), contains('54,00'));
      expect(emReais(123456), contains('1.234,56'));
    });

    test('a soma acontece em centavos, sem ponto flutuante', () {
      // O caso clássico: 0,1 + 0,2 em double dá 0,30000000000000004. Em
      // centavos, 10 + 20 = 30, e é por isso que o schema exige inteiro.
      const a = 10, b = 20;
      expect(a + b, 30);
      expect(emReais(a + b), contains('0,30'));
    });
  });

  group('promoção', () {
    final agora = DateTime.now();

    test('vale dentro da janela', () {
      final p = produto(
        promo: 1900,
        comeca: agora.subtract(const Duration(hours: 1)),
        termina: agora.add(const Duration(hours: 1)),
      );
      expect(p.emPromocao, isTrue);
      expect(p.precoQueVale, 1900);
    });

    test('não vale antes de começar', () {
      final p = produto(promo: 1900, comeca: agora.add(const Duration(days: 1)));
      expect(p.emPromocao, isFalse);
      expect(p.precoQueVale, 2500);
    });

    test('não vale depois de vencer', () {
      final p = produto(
          promo: 1900, termina: agora.subtract(const Duration(minutes: 1)));
      expect(p.emPromocao, isFalse);
      expect(p.precoQueVale, 2500);
    });

    test('sem janela, promoção cadastrada vale sempre', () {
      expect(produto(promo: 1900).precoQueVale, 1900);
    });
  });

  group('disponibilidade', () {
    test('esgotado é diferente de indisponível', () {
      final semEstoque = produto(controlaEstoque: true, estoque: 0);
      expect(semEstoque.esgotado, isTrue);
      expect(semEstoque.podeSerPedido, isFalse);

      final foraDoAr = produto(disponivel: false);
      expect(foraDoAr.esgotado, isFalse);
      expect(foraDoAr.podeSerPedido, isFalse);
    });

    test('quem não controla estoque nunca esgota sozinho', () {
      expect(produto(controlaEstoque: false, estoque: 0).esgotado, isFalse);
    });
  });

  group('frete', () {
    test('cobra a taxa abaixo do valor de frete grátis', () {
      expect(restaurante(taxa: 700, gratisAcima: 8000).taxaPara(5400), 700);
    });

    test('zera a taxa a partir do valor cadastrado', () {
      expect(restaurante(taxa: 700, gratisAcima: 8000).taxaPara(8000), 0);
      expect(restaurante(taxa: 700, gratisAcima: 8000).taxaPara(9000), 0);
    });

    test('sem frete grátis cadastrado, a taxa vale sempre', () {
      expect(restaurante(taxa: 700).taxaPara(50000), 700);
    });
  });

  group('item do carrinho', () {
    final adicional = Adicional(
      id: 'a1',
      grupoId: 'g1',
      nome: 'Bem passada',
      precoCentavos: 200,
      disponivel: true,
      posicao: 0,
      quantidadeMaxima: 1,
    );

    test('adicional entra no preço unitário antes de multiplicar', () {
      final item = ItemDoCarrinho(
        id: 'i1',
        produto: produto(),
        quantidade: 2,
        adicionais: [AdicionalEscolhido(adicional: adicional)],
      );
      // (2500 + 200) x 2 = 5400 — a mesma conta que fechar_pedido faz no banco.
      expect(item.totalCentavos, 5400);
    });

    test('adicional com quantidade maior multiplica só ele', () {
      final item = ItemDoCarrinho(
        id: 'i1',
        produto: produto(),
        quantidade: 1,
        adicionais: [AdicionalEscolhido(adicional: adicional, quantidade: 3)],
      );
      expect(item.adicionaisCentavos, 600);
      expect(item.totalCentavos, 3100);
    });
  });

  group('máquina de estados do pedido', () {
    test('o caminho normal de uma entrega é permitido', () {
      const caminho = [
        StatusDoPedido.recebido,
        StatusDoPedido.confirmado,
        StatusDoPedido.emPreparo,
        StatusDoPedido.pronto,
        StatusDoPedido.saiuParaEntrega,
        StatusDoPedido.entregue,
      ];
      for (var i = 0; i < caminho.length - 1; i++) {
        expect(transicaoPermitida(caminho[i], caminho[i + 1]), isTrue,
            reason: '${caminho[i]} -> ${caminho[i + 1]}');
      }
    });

    test('retirada conclui direto de pronto', () {
      expect(
          transicaoPermitida(StatusDoPedido.pronto, StatusDoPedido.entregue),
          isTrue);
    });

    test('não se pula etapa', () {
      expect(
          transicaoPermitida(StatusDoPedido.recebido, StatusDoPedido.entregue),
          isFalse);
    });

    test('estado final não tem saída', () {
      for (final terminal in [
        StatusDoPedido.entregue,
        StatusDoPedido.cancelado,
        StatusDoPedido.recusado,
      ]) {
        for (final destino in StatusDoPedido.values) {
          expect(transicaoPermitida(terminal, destino), isFalse,
              reason: '$terminal -> $destino');
        }
      }
    });

    test('todo estado tem uma entrada no mapa — inclusive os finais', () {
      // Sem isto, um estado novo no banco passaria despercebido aqui e a tela
      // silenciosamente nunca ofereceria o próximo passo.
      for (final s in StatusDoPedido.values) {
        expect(transicoesPermitidas.containsKey(s), isTrue, reason: '$s');
      }
    });
  });

  group('enums espelham o banco', () {
    test('cada valor volta do texto que o Postgres usa', () {
      expect(StatusDoPedido.de('out_for_delivery'),
          StatusDoPedido.saiuParaEntrega);
      expect(TipoDeEntrega.de('pickup'), TipoDeEntrega.retirada);
      expect(FormaDePagamento.de('meal_voucher'), FormaDePagamento.valeRefeicao);
      expect(StatusDaEntrega.de('heading_to_customer'),
          StatusDaEntrega.indoAoCliente);
    });

    test('valor desconhecido estoura em vez de virar outra coisa', () {
      // Se o banco ganhar um estado novo e este arquivo ficar para trás, o
      // aplicativo precisa falhar alto. Silêncio aqui viraria um pedido em
      // estado desconhecido aparecendo como "recebido" na tela do balcão.
      expect(() => StatusDoPedido.de('teletransportado'), throwsArgumentError);
    });

    test('só dinheiro aceita troco', () {
      expect(FormaDePagamento.dinheiro.aceitaTroco, isTrue);
      for (final f in FormaDePagamento.values.where(
          (f) => f != FormaDePagamento.dinheiro)) {
        expect(f.aceitaTroco, isFalse, reason: f.name);
      }
    });
  });

  group('grupo de adicionais', () {
    test('obrigatório de escolha única vira "Escolha 1"', () {
      const g = GrupoDeAdicionais(
        id: 'g1',
        produtoId: 'p1',
        nome: 'Ponto da carne',
        obrigatorio: true,
        minimo: 1,
        maximo: 1,
        posicao: 0,
        adicionais: [],
      );
      expect(g.escolhaUnica, isTrue);
      expect(g.regra, 'Escolha 1');
    });

    test('opcional de múltipla escolha mostra o teto', () {
      const g = GrupoDeAdicionais(
        id: 'g2',
        produtoId: 'p1',
        nome: 'Extras',
        obrigatorio: false,
        minimo: 0,
        maximo: 3,
        posicao: 1,
        adicionais: [],
      );
      expect(g.escolhaUnica, isFalse);
      expect(g.regra, 'Até 3');
    });
  });

  group('formato', () {
    test('telefone de 11 dígitos vira (27) 99999-8888', () {
      expect(telefone('27999998888'), '(27) 99999-8888');
    });

    test('faixa de tempo soma preparo e entrega', () {
      expect(faixaDeMinutos(30, 20), '50–70 min');
    });

    test('distância curta aparece em metros', () {
      expect(distanciaKm(0.4), '400 m');
      expect(distanciaKm(2.35), '2.4 km');
    });
  });
}
