/// Busca de endereço por CEP.
///
/// Duas fontes, na ordem: ViaCEP e, se ela não responder, BrasilAPI. Não é
/// exagero — num aplicativo de delivery o cadastro de endereço acontece com o
/// cliente com fome, e ficar refém de um serviço fora do ar é perder o pedido.
///
/// **Nada aqui trava o formulário.** CEP não encontrado, serviço fora, celular
/// sem rede: tudo devolve nulo, e a pessoa digita o endereço como sempre pôde.
/// O preenchimento automático é um atalho, não um requisito.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class EnderecoDoCep {
  const EnderecoDoCep({
    required this.cep,
    required this.rua,
    required this.bairro,
    required this.cidade,
    required this.uf,
  });

  final String cep;
  final String rua;
  final String bairro;
  final String cidade;
  final String uf;

  /// CEP de município inteiro — os terminados em 000 de cidades pequenas —
  /// vem sem rua nem bairro. A tela precisa saber disso para não parecer que
  /// a busca falhou quando ela achou.
  bool get temRua => rua.isNotEmpty;

  /// ViaCEP: `{ logradouro, bairro, localidade, uf, erro }`.
  static EnderecoDoCep? deViaCep(Map<String, dynamic> m) {
    if (m['erro'] == true || m['erro'] == 'true') return null;
    final uf = (m['uf'] as String?) ?? '';
    if (uf.isEmpty) return null;
    return EnderecoDoCep(
      cep: _digitos((m['cep'] as String?) ?? ''),
      rua: (m['logradouro'] as String?) ?? '',
      bairro: (m['bairro'] as String?) ?? '',
      cidade: (m['localidade'] as String?) ?? '',
      uf: uf,
    );
  }

  /// BrasilAPI: `{ street, neighborhood, city, state }`.
  static EnderecoDoCep? deBrasilApi(Map<String, dynamic> m) {
    final uf = (m['state'] as String?) ?? '';
    if (uf.isEmpty) return null;
    return EnderecoDoCep(
      cep: _digitos((m['cep'] as String?) ?? ''),
      rua: (m['street'] as String?) ?? '',
      bairro: (m['neighborhood'] as String?) ?? '',
      cidade: (m['city'] as String?) ?? '',
      uf: uf,
    );
  }
}

String _digitos(String v) => v.replaceAll(RegExp(r'\D'), '');

/// Formata para 00000-000 enquanto a pessoa digita.
String cepFormatado(String bruto) {
  final d = _digitos(bruto);
  if (d.length <= 5) return d;
  return '${d.substring(0, 5)}-${d.substring(5, d.length.clamp(5, 8))}';
}

bool cepCompleto(String bruto) => _digitos(bruto).length == 8;

class Cep {
  /// Quanto tempo esperar por cada serviço.
  ///
  /// Curto de propósito: o atalho vale enquanto for rápido. Passou disso, é
  /// mais rápido a pessoa digitar do que ficar olhando o campo girar.
  static const _limite = Duration(seconds: 6);

  static Future<EnderecoDoCep?> buscar(String bruto) async {
    final cep = _digitos(bruto);
    if (cep.length != 8) return null;

    final viaCep = await _tentar(
      Uri.parse('https://viacep.com.br/ws/$cep/json/'),
      EnderecoDoCep.deViaCep,
    );
    if (viaCep != null) return viaCep;

    return _tentar(
      Uri.parse('https://brasilapi.com.br/api/cep/v2/$cep'),
      EnderecoDoCep.deBrasilApi,
    );
  }

  static Future<EnderecoDoCep?> _tentar(
    Uri endereco,
    EnderecoDoCep? Function(Map<String, dynamic>) ler,
  ) async {
    try {
      final r = await http.get(endereco).timeout(_limite);
      if (r.statusCode != 200) return null;
      // O corpo vem em UTF-8 sem o cabeçalho dizer; sem isto, "São Paulo"
      // chega com o acento quebrado.
      final corpo = jsonDecode(utf8.decode(r.bodyBytes));
      if (corpo is! Map<String, dynamic>) return null;
      return ler(corpo);
    } catch (_) {
      // Rede fora, servidor fora, resposta estranha: o formulário segue.
      return null;
    }
  }
}
