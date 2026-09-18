/// A vitrine: o que o cliente vê antes de escolher onde pedir.
///
/// Tudo aqui é legível por `anon` — as políticas "cardapio publico" e
/// "estabelecimentos aprovados sao publicos" abrem leitura para quem não
/// entrou. É de propósito: obrigar cadastro para só *olhar* o cardápio é o
/// jeito mais barato de perder um cliente com fome.
library;

import '../modelos/modelos.dart';
import 'supabase.dart';

class CategoriaDaPlataforma {
  const CategoriaDaPlataforma({
    required this.id,
    required this.slug,
    required this.nome,
    this.icone,
    this.imagemUrl,
  });

  final String id;
  final String slug;
  final String nome;
  final String? icone;
  final String? imagemUrl;

  factory CategoriaDaPlataforma.deMapa(Map<String, dynamic> m) =>
      CategoriaDaPlataforma(
        id: m['id'] as String,
        slug: m['slug'] as String,
        nome: m['name'] as String,
        icone: m['icon'] as String?,
        imagemUrl: m['image_url'] as String?,
      );
}

class Faixa {
  const Faixa({required this.id, required this.titulo, required this.imagemUrl, this.restauranteId});

  final String id;
  final String titulo;
  final String imagemUrl;
  final String? restauranteId;

  factory Faixa.deMapa(Map<String, dynamic> m) => Faixa(
        id: m['id'] as String,
        titulo: m['title'] as String,
        imagemUrl: m['image_url'] as String,
        restauranteId: m['restaurant_id'] as String?,
      );
}

class Vitrine {
  /// Os estabelecimentos aprovados, abertos primeiro.
  ///
  /// A ordenação põe loja aberta na frente porque a alternativa — ordenar só
  /// por nota — mostra o melhor restaurante da cidade, fechado, no topo de uma
  /// tela de quem quer comer agora.
  static Future<List<Restaurante>> restaurantes({
    String? busca,
    String? categoriaId,
    int limite = 50,
  }) =>
      executar(() async {
        var consulta = banco.from('restaurants').select(
              categoriaId == null
                  ? '*'
                  : '*, restaurant_platform_categories!inner(category_id)',
            );

        if (busca != null && busca.trim().isNotEmpty) {
          consulta = consulta.ilike('name', '%${busca.trim()}%');
        }
        if (categoriaId != null) {
          consulta = consulta.eq(
            'restaurant_platform_categories.category_id',
            categoriaId,
          );
        }

        final linhas = await consulta
            .order('is_open', ascending: false)
            .order('rating_avg', ascending: false)
            .limit(limite);

        return linhas.map((l) => Restaurante.deMapa(l)).toList();
      });

  static Future<List<CategoriaDaPlataforma>> categorias() => executar(() async {
        final linhas = await banco
            .from('platform_categories')
            .select()
            .eq('is_active', true)
            .order('position');
        return linhas.map((l) => CategoriaDaPlataforma.deMapa(l)).toList();
      });

  static Future<List<Faixa>> faixas() => executar(() async {
        final agora = DateTime.now().toUtc().toIso8601String();
        final linhas = await banco
            .from('banners')
            .select()
            .eq('is_active', true)
            .lte('starts_at', agora)
            .or('ends_at.is.null,ends_at.gte.$agora')
            .order('position');
        return linhas.map((l) => Faixa.deMapa(l)).toList();
      });

  /// Busca produtos em todos os cardápios — quem procura "açaí" quer o item,
  /// não necessariamente a loja.
  static Future<List<Produto>> produtos(String busca, {int limite = 30}) =>
      executar(() async {
        if (busca.trim().isEmpty) return <Produto>[];
        final linhas = await banco
            .from('products')
            .select()
            .eq('is_available', true)
            .isFilter('deleted_at', null)
            .ilike('name', '%${busca.trim()}%')
            .limit(limite);
        return linhas.map((l) => Produto.deMapa(l)).toList();
      });
}
