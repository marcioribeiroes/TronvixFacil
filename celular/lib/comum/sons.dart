/// Os sons do aplicativo.
///
/// Um sino de recepção — o sininho de balcão. Sintetizado por
/// `tool/gerar_sons.dart`, não baixado: efeito sonoro publicado na internet
/// tem dono, e embutir um num produto que se vende é problema de licença que
/// aparece tarde.
///
/// **Nada aqui derruba a tela.** Aparelho no silencioso, áudio ocupado por
/// outro app, permissão negada: tudo vira silêncio, não exceção. Som é
/// acabamento; a informação está na tela.
library;

import 'package:audioplayers/audioplayers.dart';

enum Toque {
  /// Ao abrir o aplicativo e quando o pedido é entregue: o sino inteiro.
  cheio('sons/sino.wav'),

  /// A cada passo do pedido. O mesmo sino, mais curto e mais discreto — um
  /// toque longo repetido cinco vezes cansa antes de a comida chegar.
  curto('sons/sino-curto.wav');

  const Toque(this.arquivo);
  final String arquivo;
}

class Sons {
  /// Um tocador por vez. Reaproveitar a instância evita o estalo de abrir e
  /// fechar a saída de áudio a cada toque.
  ///
  /// Sem o `positionUpdater`: o padrão do audioplayers registra um callback de
  /// quadro para dizer em que segundo o áudio está, e ele continua rodando
  /// depois que o som acaba. Num teste isso estoura com "An animation is still
  /// running even after the widget tree was disposed"; no aplicativo é um
  /// ticker vivo à toa.
  ///
  /// Ninguém aqui pergunta a posição do áudio — são toques de meio segundo.
  static final _tocador = AudioPlayer()..positionUpdater = null;

  static bool _ligado = true;

  /// Desligar vale para o aplicativo inteiro. Quem não quer som não quer em
  /// nenhuma tela.
  static void silenciar(bool silencio) => _ligado = !silencio;

  static bool get ligado => _ligado;

  static Future<void> tocar(Toque toque) async {
    if (!_ligado) return;
    try {
      await _tocador.stop();
      await _tocador.play(
        AssetSource(toque.arquivo),
        // Toca junto com o que estiver tocando, em vez de interromper a música
        // de quem está com fone. O aviso não precisa do palco inteiro.
        mode: PlayerMode.lowLatency,
      );
    } catch (_) {
      // Silêncio é uma falha aceitável.
    }
  }
}
