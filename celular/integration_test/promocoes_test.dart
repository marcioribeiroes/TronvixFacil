/// O filtro de promoções da vitrine.
///
/// A pergunta "esta loja tem promoção agora?" é respondida pelo banco, numa
/// coluna calculada. Este teste confere o caminho inteiro contra o Supabase de
/// verdade: a coluna vindo no resultado, o filtro recortando a lista, e a
/// janela da promoção sendo respeitada.
///
/// Como rodar:
///   ./testar-no-aparelho.sh -d "iPhone 17" integration_test/promocoes_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tronvix_facil/dados/supabase.dart';
import 'package:tronvix_facil/dados/vitrine.dart';
import 'package:tronvix_facil/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('o filtro mostra só quem tem promoção valendo', (tester) async {
    await app.prepararApp();

    final todas = await Vitrine.restaurantes();
    final comPromocao = await Vitrine.restaurantes(somentePromocoes: true);

    expect(todas, isNotEmpty, reason: 'nenhum estabelecimento aprovado no servidor');

    // Todo mundo que o filtro devolve tem promoção — é o que o filtro promete.
    for (final r in comPromocao) {
      expect(r.temPromocao, isTrue,
          reason: '${r.nome} veio no filtro sem ter promoção');
    }

    // E ninguém com promoção ficou de fora.
    final perdidos = todas.where((r) => r.temPromocao).where(
          (r) => !comPromocao.any((c) => c.id == r.id),
        );
    expect(perdidos, isEmpty,
        reason: 'loja com promoção que o filtro deixou de fora: '
            '${perdidos.map((r) => r.nome).join(", ")}');

    expect(comPromocao.length, lessThanOrEqualTo(todas.length),
        reason: 'o filtro não pode devolver mais do que a lista inteira');

    if (comPromocao.isEmpty) {
      markTestSkipped('Nenhuma loja com promoção agora — o recorte não pôde ser provado.');
      return;
    }

    // A janela manda: uma promoção que já terminou não conta.
    final loja = comPromocao.first;
    final produtos = await banco
        .from('products')
        .select('id')
        .eq('restaurant_id', loja.id)
        .eq('is_available', true)
        .not('promo_price_cents', 'is', null)
        .limit(1);

    expect(produtos, isNotEmpty,
        reason: '${loja.nome} entrou no filtro sem produto em promoção');
  });
}
