/// Quem está usando o aplicativo, e por isso qual dos três fluxos abrir.
///
/// Um aplicativo, três públicos. A escolha não é um menu: é consequência do
/// que a pessoa é no banco.
///
///   tem vínculo ativo em restaurant_members  -> fluxo do restaurante
///   tem cadastro em couriers                 -> fluxo do entregador
///   qualquer outra pessoa autenticada        -> fluxo do cliente
///
/// A ordem importa e foi escolhida: um dono de restaurante que também pede
/// comida abre no balcão, porque é lá que ele perde dinheiro se demorar a ver
/// um pedido. Trocar de fluxo continua possível pela conta — mas o padrão
/// atende o caso urgente.
library;

import 'package:flutter/foundation.dart';

import 'dados/supabase.dart';
import 'modelos/modelos.dart';

enum Fluxo { cliente, restaurante, entregador }

class Sessao extends ChangeNotifier {
  Sessao._();
  static final Sessao instancia = Sessao._();

  Perfil? _perfil;
  Entregador? _entregador;
  VinculoComRestaurante? _vinculo;
  Fluxo? _fluxoEscolhido;
  bool _carregando = false;

  Perfil? get perfil => _perfil;
  Entregador? get entregador => _entregador;
  VinculoComRestaurante? get vinculo => _vinculo;
  bool get carregando => _carregando;
  bool get autenticado => _perfil != null;

  /// Os fluxos que esta pessoa pode abrir. Quem só é cliente vê um só, e a
  /// troca de fluxo nem aparece na conta.
  List<Fluxo> get fluxosDisponiveis => [
        Fluxo.cliente,
        if (_vinculo != null) Fluxo.restaurante,
        if (_entregador != null) Fluxo.entregador,
      ];

  Fluxo get fluxo =>
      _fluxoEscolhido ??
      (_vinculo != null
          ? Fluxo.restaurante
          : _entregador != null
              ? Fluxo.entregador
              : Fluxo.cliente);

  void trocarDeFluxo(Fluxo novo) {
    if (!fluxosDisponiveis.contains(novo)) return;
    _fluxoEscolhido = novo;
    notifyListeners();
  }

  /// Lê no banco quem é a pessoa autenticada.
  ///
  /// Três consultas em paralelo, não em sequência: são independentes e a
  /// primeira tela do aplicativo espera por todas.
  Future<void> carregar() async {
    final id = usuarioId;
    if (id == null) {
      _perfil = null;
      _entregador = null;
      _vinculo = null;
      _fluxoEscolhido = null;
      notifyListeners();
      return;
    }

    _carregando = true;
    notifyListeners();

    try {
      final resultados = await Future.wait([
        banco.from('profiles').select().eq('id', id).maybeSingle(),
        banco
            .from('couriers')
            // O nome do estabelecimento vem junto: a tela do entregador fala
            // dele o tempo todo — quem aprova, de quem é a corrida.
            .select('*, restaurants(name)')
            .eq('user_id', id)
            .isFilter('deleted_at', null)
            .maybeSingle(),
        banco
            .from('restaurant_members')
            .select('restaurant_id, role, restaurants(name)')
            .eq('user_id', id)
            .eq('is_active', true)
            .isFilter('deleted_at', null)
            .limit(1)
            .maybeSingle(),
      ]);

      // Trocou de conta enquanto isto voltava? Então este resultado é de outra
      // sessão e não pode ser aplicado.
      //
      // Acontece de verdade: `sair()` seguido de `entrar()` dispara o ouvinte
      // de autenticação, que chama este método em paralelo com o `entrar`. Sem
      // esta conferência, quem terminasse por último ganhava — e às vezes quem
      // terminava por último era a leitura de uma sessão que já não existe.
      if (usuarioId != id) return;

      final p = resultados[0];
      final c = resultados[1];
      final v = resultados[2];

      _perfil = p == null ? null : Perfil.deMapa(p);
      _entregador = c == null ? null : Entregador.deMapa(c);
      _vinculo = v == null ? null : VinculoComRestaurante.deMapa(v);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> entrar(String email, String senha) async {
    await executar(() => autenticacao.signInWithPassword(
          email: email.trim(),
          password: senha,
        ));
    await carregar();
  }

  /// Cadastro de cliente.
  ///
  /// O papel vai nos metadados porque quem cria o perfil é o gatilho
  /// `app.handle_new_user`, na mesma transação do Auth. Preencher `profiles`
  /// daqui abriria a janela em que a pessoa está autenticada e ainda não tem
  /// papel — e toda política de RLS quebraria em silêncio nessa janela.
  Future<void> criarConta({
    required String nome,
    required String email,
    required String senha,
    String? telefone,
  }) async {
    await executar(() => autenticacao.signUp(
          email: email.trim(),
          password: senha,
          data: {
            'full_name': nome.trim(),
            if (telefone != null && telefone.isNotEmpty)
              'phone': telefone.replaceAll(RegExp(r'\D'), ''),
            'platform_role': 'customer',
          },
        ));
    await carregar();
  }

  Future<void> sair() async {
    await executar(() => autenticacao.signOut());
    _perfil = null;
    _entregador = null;
    _vinculo = null;
    _fluxoEscolhido = null;
    notifyListeners();
  }

  Future<void> recuperarSenha(String email) =>
      executar(() => autenticacao.resetPasswordForEmail(email.trim()));

  Future<void> atualizarPerfil({String? nome, String? telefone}) async {
    final id = usuarioId;
    if (id == null) return;
    await executar(() => banco.from('profiles').update({
          if (nome != null) 'full_name': nome.trim(),
          if (telefone != null)
            'phone': telefone.isEmpty
                ? null
                : telefone.replaceAll(RegExp(r'\D'), ''),
        }).eq('id', id));
    await carregar();
  }
}
