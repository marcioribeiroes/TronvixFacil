/// Quanto custa a entrega, e se a loja entrega.
///
/// A conta é do banco (`cotar_entrega`, `lojas_para_o_endereco`): a mesma que
/// o site e o fechamento do pedido usam. Aqui só se lê.
library;

import 'supabase.dart';

class CotacaoDeEntrega {
  const CotacaoDeEntrega({required this.entrega, this.km, this.taxaCentavos});

  factory CotacaoDeEntrega.deMapa(Map<String, dynamic> m) => CotacaoDeEntrega(
    entrega: m['entrega'] as bool? ?? true,
    km: (m['km'] as num?)?.toDouble(),
    taxaCentavos: (m['taxa_cents'] as num?)?.toInt(),
  );

  final bool entrega;
  final double? km;

  /// Taxa da faixa, sem o frete grátis por valor — esse depende do carrinho.
  final int? taxaCentavos;

  String get distancia =>
      km == null ? '' : '${km!.toStringAsFixed(1).replaceAll('.', ',')} km';
}

class TaxaDeEntrega {
  /// A cotação da loja para cada endereço do cliente.
  static Future<Map<String, CotacaoDeEntrega>> paraEnderecos(
    String restauranteId,
    List<String> enderecos,
  ) => executar(() async {
    final pares = await Future.wait(
      enderecos.map((id) async {
        final dados = await banco.rpc(
          'cotar_entrega',
          params: {
            'p_restaurante': restauranteId,
            'p_endereco': id,
            'p_subtotal_cents': 0,
          },
        );
        return MapEntry(
          id,
          CotacaoDeEntrega.deMapa(dados as Map<String, dynamic>),
        );
      }),
    );
    return Map.fromEntries(pares);
  });

  /// Todas as lojas para um endereço: quem entrega, a quantos km, por quanto.
  static Future<Map<String, CotacaoDeEntrega>> lojasPara(String enderecoId) =>
      executar(() async {
        final linhas = await banco.rpc(
          'lojas_para_o_endereco',
          params: {'p_endereco': enderecoId},
        );
        return {
          for (final l in (linhas as List).cast<Map<String, dynamic>>())
            l['restaurant_id'] as String: CotacaoDeEntrega.deMapa(l),
        };
      });
}
