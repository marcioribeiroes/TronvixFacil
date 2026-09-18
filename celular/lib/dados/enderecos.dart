/// Os endereços do cliente.
library;

import '../modelos/modelos.dart';
import 'localizacao.dart';
import 'supabase.dart';

class Enderecos {
  static Future<List<Endereco>> meus() => executar(() async {
        final id = usuarioId;
        if (id == null) return <Endereco>[];
        final linhas = await banco
            .from('addresses')
            .select()
            .eq('user_id', id)
            .isFilter('deleted_at', null)
            .order('is_default', ascending: false)
            .order('created_at');
        return linhas.map((l) => Endereco.deMapa(l)).toList();
      });

  static Future<Endereco> salvar({
    String? id,
    required String rotulo,
    required String rua,
    required String numero,
    required String bairro,
    required String cidade,
    required String uf,
    required String cep,
    String? complemento,
    String? referencia,
    bool padrao = false,
    Ponto? ponto,
  }) =>
      executar(() async {
        final usuario = usuarioId;
        if (usuario == null) {
          throw ErroDeDados('Entre na sua conta para salvar um endereço.');
        }

        // Só pode haver um padrão por cliente, e quem garante é um índice
        // único. Baixar o anterior antes evita que o banco recuse a gravação
        // com uma mensagem que não ajudaria ninguém na tela.
        if (padrao) {
          await banco
              .from('addresses')
              .update({'is_default': false})
              .eq('user_id', usuario)
              .eq('is_default', true);
        }

        final dados = {
          'user_id': usuario,
          'label': rotulo,
          'street': rua,
          'number': numero,
          'district': bairro,
          'city': cidade,
          'state': uf.toUpperCase(),
          'postal_code': cep.replaceAll(RegExp(r'\D'), ''),
          'complement': complemento?.isEmpty == true ? null : complemento,
          'reference_point': referencia?.isEmpty == true ? null : referencia,
          'is_default': padrao,
          // Só grava coordenada quando existe de verdade. Endereço sem ponto é
          // normal; ponto errado é o entregador na rua de trás.
          if (ponto != null) 'latitude': ponto.latitude,
          if (ponto != null) 'longitude': ponto.longitude,
        };

        final linha = id == null
            ? await banco.from('addresses').insert(dados).select().single()
            : await banco
                .from('addresses')
                .update(dados)
                .eq('id', id)
                .select()
                .single();

        return Endereco.deMapa(linha);
      });

  /// Exclusão lógica: um pedido antigo aponta para este endereço, e apagar de
  /// verdade deixaria a entrega de ontem sem destino.
  static Future<void> remover(String id) => executar(() async {
        await banco
            .from('addresses')
            .update({
              'deleted_at': DateTime.now().toUtc().toIso8601String(),
              'is_default': false,
            })
            .eq('id', id);
      });

  static Future<void> tornarPadrao(String id) => executar(() async {
        final usuario = usuarioId;
        if (usuario == null) return;
        await banco
            .from('addresses')
            .update({'is_default': false})
            .eq('user_id', usuario)
            .eq('is_default', true);
        await banco.from('addresses').update({'is_default': true}).eq('id', id);
      });
}
