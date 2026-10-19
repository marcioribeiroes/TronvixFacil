/// Os erros do aplicativo vão para o mesmo registro do site (/admin/erros).
///
/// Sem isto, uma tela quebrando no celular de um cliente não deixava rastro em
/// lugar nenhum. O envio nunca lança: registrar um erro não pode virar outro.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../dados/supabase.dart';

class RegistroDeErros {
  RegistroDeErros._();

  /// A versão do pubspec, para saber em qual compilação o erro aconteceu.
  static const versao = String.fromEnvironment('VERSAO', defaultValue: '1.0.0+3');

  static bool _enviando = false;

  /// Liga a captura. Erro do Flutter (tela) e erro fora dele (async) — os dois
  /// caminhos por onde um erro escapa sem ninguém ver.
  static void ligar() {
    final anterior = FlutterError.onError;
    FlutterError.onError = (detalhes) {
      anterior?.call(detalhes);
      registrar(detalhes.exception, detalhes.stack, contexto: detalhes.context?.toString());
    };

    PlatformDispatcher.instance.onError = (erro, pilha) {
      registrar(erro, pilha);
      return true;
    };
  }

  static void registrar(Object erro, StackTrace? pilha, {String? contexto}) {
    // Em desenvolvimento o erro já aparece no terminal; o registro é para o
    // que acontece no celular dos outros.
    if (kDebugMode) return;
    // Um erro dentro do próprio envio não pode virar um laço.
    if (_enviando) return;
    _enviando = true;
    unawaited(() async {
      try {
        await banco.rpc('registrar_erro', params: {
          'p_origem': 'app',
          'p_mensagem': erro.toString(),
          'p_pilha': pilha?.toString(),
          'p_endereco': contexto,
          'p_versao': versao,
          'p_contexto': {
            'plataforma': Platform.operatingSystem,
            'sistema': Platform.operatingSystemVersion,
          },
        });
      } catch (_) {
        // Sem rede, sem registro.
      } finally {
        _enviando = false;
      }
    }());
  }
}
