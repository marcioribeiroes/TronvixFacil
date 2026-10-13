/// O caixa do balcão: fundo, recebimentos, sangrias.
///
/// Tudo vem de `movimento_do_caixa`, a mesma função que alimenta o caixa e o
/// relatório do painel web. O dia é calculado no banco, no fuso da loja — o
/// celular não decide onde começa o dia, e por isso não discorda do painel.
library;

import '../modelos/enums.dart';
import 'supabase.dart';

enum TipoDeLancamento {
  fundo('opening_float', 'Fundo de caixa'),
  sangria('withdrawal', 'Sangria');

  const TipoDeLancamento(this.noBanco, this.rotulo);
  final String noBanco;
  final String rotulo;

  static TipoDeLancamento de(String v) =>
      values.firstWhere((e) => e.noBanco == v);
}

class LancamentoDoCaixa {
  const LancamentoDoCaixa({
    required this.id,
    required this.tipo,
    required this.valorCentavos,
    required this.feitoEm,
    this.observacao,
    this.feitoPor,
    this.canceladoEm,
  });

  factory LancamentoDoCaixa.deMapa(Map<String, dynamic> m) => LancamentoDoCaixa(
    id: m['id'] as String,
    tipo: TipoDeLancamento.de(m['tipo'] as String),
    valorCentavos: (m['valor_cents'] as num).toInt(),
    feitoEm: DateTime.parse(m['feito_em'] as String),
    observacao: m['observacao'] as String?,
    feitoPor: m['feito_por'] as String?,
    canceladoEm: m['cancelado_em'] == null
        ? null
        : DateTime.parse(m['cancelado_em'] as String),
  );

  final String id;
  final TipoDeLancamento tipo;
  final int valorCentavos;
  final DateTime feitoEm;
  final String? observacao;
  final String? feitoPor;
  final DateTime? canceladoEm;

  bool get cancelado => canceladoEm != null;
}

/// Um pedido no caixa: recebido (com forma e hora) ou ainda a receber.
class PedidoNoCaixa {
  const PedidoNoCaixa({
    required this.pedidoId,
    required this.numero,
    required this.cliente,
    required this.tipo,
    required this.forma,
    required this.valorCentavos,
    this.mesa,
    this.pelaInternet = false,
    this.pagoEm,
  });

  factory PedidoNoCaixa.deMapa(Map<String, dynamic> m) => PedidoNoCaixa(
    pedidoId: m['pedido_id'] as String,
    numero: (m['numero'] as num).toInt(),
    cliente: m['cliente'] as String,
    tipo: TipoDeEntrega.de(m['tipo_de_entrega'] as String),
    mesa: m['mesa'] as String?,
    forma: FormaDePagamento.de(m['forma'] as String),
    valorCentavos: (m['valor_cents'] as num).toInt(),
    pelaInternet: m['momento'] == MomentoDoPagamento.noApp.noBanco,
    pagoEm: m['pago_em'] == null
        ? null
        : DateTime.parse(m['pago_em'] as String),
  );

  final String pedidoId;
  final int numero;
  final String cliente;
  final TipoDeEntrega tipo;
  final String? mesa;
  final FormaDePagamento forma;
  final int valorCentavos;
  final bool pelaInternet;
  final DateTime? pagoEm;

  String get destino =>
      tipo == TipoDeEntrega.mesa ? (mesa ?? 'Mesa') : tipo.rotulo;
}

class MovimentoDoCaixa {
  const MovimentoDoCaixa({
    required this.dinheiroNaGavetaCentavos,
    required this.lancamentos,
    required this.recebimentos,
    required this.aReceber,
  });

  factory MovimentoDoCaixa.deMapa(Map<String, dynamic> m) {
    List<Map<String, dynamic>> lista(String chave) =>
        ((m[chave] as List?) ?? const []).cast<Map<String, dynamic>>();

    return MovimentoDoCaixa(
      dinheiroNaGavetaCentavos: (m['dinheiro_na_gaveta_cents'] as num).toInt(),
      lancamentos: lista('lancamentos').map(LancamentoDoCaixa.deMapa).toList(),
      recebimentos: lista('recebimentos').map(PedidoNoCaixa.deMapa).toList(),
      aReceber: lista('a_receber').map(PedidoNoCaixa.deMapa).toList(),
    );
  }

  final int dinheiroNaGavetaCentavos;
  final List<LancamentoDoCaixa> lancamentos;
  final List<PedidoNoCaixa> recebimentos;
  final List<PedidoNoCaixa> aReceber;

  /// Cancelado aparece riscado, mas não entra em soma nenhuma.
  int _soma(TipoDeLancamento tipo) => lancamentos
      .where((l) => l.tipo == tipo && !l.cancelado)
      .fold(0, (s, l) => s + l.valorCentavos);

  int get fundoCentavos => _soma(TipoDeLancamento.fundo);
  int get sangriasCentavos => _soma(TipoDeLancamento.sangria);
  bool get temFundo =>
      lancamentos.any((l) => l.tipo == TipoDeLancamento.fundo && !l.cancelado);

  int get recebidoCentavos =>
      recebimentos.fold(0, (s, r) => s + r.valorCentavos);

  int get aReceberCentavos => aReceber.fold(0, (s, r) => s + r.valorCentavos);

  int porForma(FormaDePagamento forma) => recebimentos
      .where((r) => r.forma == forma)
      .fold(0, (s, r) => s + r.valorCentavos);
}

class Caixa {
  static Future<MovimentoDoCaixa> movimento(String restauranteId) =>
      executar(() async {
        final dados = await banco.rpc(
          'movimento_do_caixa',
          params: {'p_restaurante': restauranteId},
        );
        return MovimentoDoCaixa.deMapa(dados as Map<String, dynamic>);
      });

  /// Um por dia. O banco recusa o segundo.
  static Future<void> registrarFundo(String restauranteId, int centavos) =>
      executar(
        () => banco.rpc(
          'registrar_fundo_de_caixa',
          params: {'p_restaurante': restauranteId, 'p_valor_cents': centavos},
        ),
      );

  /// Com motivo, e nunca mais do que há em dinheiro na gaveta.
  static Future<void> registrarSangria(
    String restauranteId,
    int centavos,
    String motivo,
  ) => executar(
    () => banco.rpc(
      'registrar_sangria',
      params: {
        'p_restaurante': restauranteId,
        'p_valor_cents': centavos,
        'p_motivo': motivo,
      },
    ),
  );

  /// Só a gestão, só de hoje. O lançamento fica, riscado.
  static Future<void> cancelar(String lancamentoId) => executar(
    () => banco.rpc(
      'cancelar_movimento_de_caixa',
      params: {'p_movimento': lancamentoId},
    ),
  );

  /// O caixa muda quando alguém recebe (`payments`), quando entra ou sai
  /// pedido (`orders`) e quando há fundo ou sangria (`cash_movements`).
  /// `payments` não tem restaurant_id para filtrar; a RLS já só entrega os
  /// pagamentos que esta pessoa pode ver.
  static RealtimeChannel acompanhar(
    String restauranteId,
    void Function() aoMudar,
  ) {
    PostgresChangeFilter daLoja() => PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'restaurant_id',
      value: restauranteId,
    );

    final canal = banco.channel('caixa:$restauranteId');
    canal
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'payments',
          callback: (_) => aoMudar(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: daLoja(),
          callback: (_) => aoMudar(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'cash_movements',
          filter: daLoja(),
          callback: (_) => aoMudar(),
        )
        .subscribe();
    return canal;
  }
}
