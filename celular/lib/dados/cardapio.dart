/// O cardápio de um estabelecimento.
library;

import '../modelos/modelos.dart';
import 'supabase.dart';

/// Uma seção do cardápio com os produtos dentro. A tela desenha exatamente
/// isto: título e lista.
class SecaoDoCardapio {
  const SecaoDoCardapio({required this.categoria, required this.produtos});
  final Categoria categoria;
  final List<Produto> produtos;
}

class Cardapio {
  static Future<Restaurante> restaurante(String id) => executar(() async {
        final linha = await banco.from('restaurants').select().eq('id', id).single();
        return Restaurante.deMapa(linha);
      });

  static Future<Restaurante> restaurantePorSlug(String slug) =>
      executar(() async {
        final linha =
            await banco.from('restaurants').select().eq('slug', slug).single();
        return Restaurante.deMapa(linha);
      });

  /// Categorias e produtos em duas consultas, não em N+1.
  ///
  /// Um cardápio de pizzaria tem 12 seções; buscar os produtos seção a seção
  /// seriam 13 idas ao servidor num celular em rede de rua.
  static Future<List<SecaoDoCardapio>> secoes(String restauranteId) =>
      executar(() async {
        final resultados = await Future.wait([
          banco
              .from('categories')
              .select()
              .eq('restaurant_id', restauranteId)
              .eq('is_active', true)
              .isFilter('deleted_at', null)
              .order('position'),
          banco
              .from('products')
              .select()
              .eq('restaurant_id', restauranteId)
              .isFilter('deleted_at', null)
              .order('position'),
        ]);

        final categorias =
            (resultados[0]).map((l) => Categoria.deMapa(l)).toList();
        final produtos = (resultados[1]).map((l) => Produto.deMapa(l)).toList();

        return categorias
            .map((c) => SecaoDoCardapio(
                  categoria: c,
                  produtos:
                      produtos.where((p) => p.categoriaId == c.id).toList(),
                ))
            .where((s) => s.produtos.isNotEmpty)
            .toList();
      });

  static Future<List<Produto>> destaques(String restauranteId) =>
      executar(() async {
        final linhas = await banco
            .from('products')
            .select()
            .eq('restaurant_id', restauranteId)
            .eq('is_featured', true)
            .eq('is_available', true)
            .isFilter('deleted_at', null)
            .order('position')
            .limit(10);
        return linhas.map((l) => Produto.deMapa(l)).toList();
      });

  /// Os grupos de adicionais de um produto, com os adicionais aninhados.
  ///
  /// O PostgREST traz o aninhamento numa consulta só; é o que `addons(*)` faz
  /// aqui. Cada grupo carrega a própria regra (obrigatório, mínimo, máximo) e a
  /// tela obedece — mas quem realmente obriga é `fechar_pedido`, no banco.
  static Future<List<GrupoDeAdicionais>> adicionais(String produtoId) =>
      executar(() async {
        final linhas = await banco
            .from('addon_groups')
            .select('*, addons(*)')
            .eq('product_id', produtoId)
            .eq('is_active', true)
            .isFilter('deleted_at', null)
            .order('position');
        return linhas.map((l) => GrupoDeAdicionais.deMapa(l)).toList();
      });

  static Future<List<FormaDePagamento>> formasAceitas(String restauranteId) =>
      executar(() async {
        final linhas = await banco
            .from('restaurant_payment_methods')
            .select('method')
            .eq('restaurant_id', restauranteId)
            .eq('is_active', true);
        return linhas
            .map((l) => FormaDePagamento.de(l['method'] as String))
            .toList();
      });
}
