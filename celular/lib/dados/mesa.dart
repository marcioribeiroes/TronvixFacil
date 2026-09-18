/// A mesa do salão.
///
/// O QR colado na mesa aponta para `<site>/m/<codigo>`. No aplicativo o que
/// interessa é só o código: a câmera lê a URL, a gente extrai o final e
/// pergunta ao banco de quem é aquela mesa.
///
/// O código nunca é digitado a partir do número da mesa, e nem se parece com
/// ele. Ler o QR é a única forma prevista; a digitação manual existe para
/// quando a câmera falha, e é o mesmo código impresso embaixo do QR.
library;

import 'package:flutter/foundation.dart';

import '../modelos/modelos.dart';
import 'supabase.dart';

class Mesa {
  const Mesa({
    required this.codigo,
    required this.rotulo,
    required this.restauranteId,
    required this.restauranteNome,
    required this.restauranteSlug,
  });

  final String codigo;
  final String rotulo;
  final String restauranteId;
  final String restauranteNome;
  final String restauranteSlug;

  factory Mesa.deMapa(Map<String, dynamic> m) {
    final loja = aninhado(m['restaurants']) ?? const <String, dynamic>{};
    return Mesa(
      codigo: m['code'] as String,
      rotulo: m['label'] as String,
      restauranteId: m['restaurant_id'] as String,
      restauranteNome: (loja['name'] as String?) ?? '',
      restauranteSlug: (loja['slug'] as String?) ?? '',
    );
  }
}

class Mesas {
  /// Extrai o código de uma leitura da câmera.
  ///
  /// O QR do sistema traz uma URL, mas nem sempre: alguém pode colar um QR
  /// gerado à mão com só o código dentro, e o código impresso embaixo da
  /// etiqueta é digitado direto. Os três casos caem aqui.
  static String? codigoDe(String leitura) {
    final texto = leitura.trim();
    if (texto.isEmpty) return null;

    final naUrl = RegExp(r'/m/([a-z0-9]{6,16})', caseSensitive: false)
        .firstMatch(texto);
    if (naUrl != null) return naUrl.group(1)!.toLowerCase();

    // QR de outra coisa — nota fiscal, Pix, cartão de visita — não vira mesa.
    if (!RegExp(r'^[a-z0-9]{6,16}$', caseSensitive: false).hasMatch(texto)) {
      return null;
    }
    return texto.toLowerCase();
  }

  /// Quem é essa mesa. Nulo quando o código não existe, a mesa está fora de
  /// uso, ou o estabelecimento não está aprovado — os três dão a mesma
  /// resposta ao cliente, porque a diferença não muda o que ele faz.
  static Future<Mesa?> porCodigo(String codigo) => executar(() async {
        final linhas = await banco
            .from('restaurant_tables')
            .select('code, label, restaurant_id, restaurants(name, slug, status)')
            .eq('code', codigo.trim().toLowerCase())
            .eq('is_active', true)
            .isFilter('deleted_at', null)
            .limit(1);

        if (linhas.isEmpty) return null;
        final mesa = Mesa.deMapa(linhas.first);

        final loja = aninhado(linhas.first['restaurants']);
        if (loja == null || loja['status'] != 'approved') return null;

        return mesa;
      });
}

/// Onde a mesa lida fica guardada enquanto a pessoa navega.
///
/// Entre ler o QR e fechar o pedido passa-se pelo cardápio, pelo produto, pelo
/// carrinho e — se não estiver logado — pelo login. Carregar o código por todas
/// essas telas como parâmetro daria uma chance a cada navegação de perder a
/// mesa, e perder a mesa é o pedido chegar à cozinha sem dizer para onde levar.
///
/// Só na memória, de propósito: fechar o aplicativo é sair da mesa. Guardar em
/// disco faria o cliente de amanhã, em casa, pedir para a mesa de hoje.
class MesaAtual extends ChangeNotifier {
  MesaAtual._();
  static final instancia = MesaAtual._();

  Mesa? _mesa;
  Mesa? get mesa => _mesa;

  /// Vale para este estabelecimento? O QR da churrascaria não serve na pizzaria.
  bool serve(String restauranteId) =>
      _mesa != null && _mesa!.restauranteId == restauranteId;

  void sentar(Mesa m) {
    _mesa = m;
    notifyListeners();
  }

  void levantar() {
    _mesa = null;
    notifyListeners();
  }
}
