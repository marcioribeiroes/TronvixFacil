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

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

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

  /// Em qual fluxo o aplicativo abre.
  ///
  /// Cliente por padrão, mesmo para quem tem loja ou entrega. Este aplicativo
  /// é, antes de tudo, o de quem pede comida — é ele que vai para a loja de
  /// aplicativos, e é a tela que um cliente novo precisa ver primeiro. O dono
  /// de restaurante que abria direto no balcão não conseguia nem ver a vitrine
  /// do próprio produto.
  ///
  /// Quem trabalha no balcão o dia inteiro não paga por isso: a escolha fica
  /// guardada, e o aplicativo reabre onde a pessoa estava.
  Fluxo get fluxo {
    final escolhido = _fluxoEscolhido;
    if (escolhido != null && fluxosDisponiveis.contains(escolhido)) {
      return escolhido;
    }
    return Fluxo.cliente;
  }

  void trocarDeFluxo(Fluxo novo) {
    if (!fluxosDisponiveis.contains(novo)) return;
    _fluxoEscolhido = novo;
    notifyListeners();
    _guardarFluxo(novo);
  }

  static const _chaveDoFluxo = 'fluxo_escolhido';

  /// Guardar e ler não travam a tela: o aplicativo abre no cliente e corrige
  /// para o fluxo guardado quando o disco responder, o que leva milissegundos.
  /// Esperar o disco para desenhar a primeira tela é trocar um erro raro por
  /// uma lentidão em toda abertura.
  Future<void> _guardarFluxo(Fluxo f) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_chaveDoFluxo, f.name);
    } catch (_) {
      // Sem disco, o aplicativo continua funcionando — só esquece a escolha.
    }
  }

  Future<void> _lerFluxoGuardado() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final nome = prefs.getString(_chaveDoFluxo);
      if (nome == null) return;

      final f = Fluxo.values.where((v) => v.name == nome).firstOrNull;
      // Só vale se a pessoa ainda pode abrir esse fluxo: quem deixou de ser
      // entregador não pode reabrir nas corridas.
      if (f != null && fluxosDisponiveis.contains(f) && _fluxoEscolhido == null) {
        _fluxoEscolhido = f;
        notifyListeners();
      }
    } catch (_) {
      // Idem.
    }
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

      // Depois de saber quem a pessoa é — e só depois, porque a escolha
      // guardada só vale se ela ainda tiver aquele fluxo.
      unawaited(_lerFluxoGuardado());
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

  /// Apaga a conta desta pessoa, de vez.
  ///
  /// Existe porque a Play Store exige o caminho dentro do aplicativo — quem
  /// deixa criar conta tem de deixar apagar — e porque a LGPD pede o mesmo.
  ///
  /// Quem decide o que pode sair é o banco: `apagar_minha_conta` recusa dono de
  /// loja, entregador e quem tem pedido em andamento, e anonimiza os pedidos
  /// antigos em vez de apagá-los, porque a venda é do restaurante. A recusa
  /// chega aqui como `ErroDeDados` já em português, e a tela mostra como está.
  Future<void> apagarConta() async {
    await executar(() => banco.rpc('apagar_minha_conta'));
    await sair();
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
