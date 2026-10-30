/// O aviso com o aplicativo fechado: pedido novo no balcão, pedido andando
/// para o cliente.
///
/// O aparelho se registra no Firebase e o token vai para o banco
/// (`registrar_aparelho`). Quem manda é a função `avisar-pedido`, a mesma que
/// já avisava no navegador. Aqui só se pede a permissão, se guarda o token e
/// se abre a tela certa quando a pessoa toca no aviso.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../cliente/acompanhar.dart';
import '../dados/supabase.dart';
import '../firebase_options.dart';
import '../sessao.dart';

class AvisosNoCelular {
  AvisosNoCelular._();

  /// O navegador do aplicativo, para abrir o pedido a partir do aviso — o
  /// toque chega fora de qualquer tela.
  static final navegador = GlobalKey<NavigatorState>();

  static bool _iniciado = false;
  static StreamSubscription<String>? _renovacao;

  /// Liga o Firebase. Falhar aqui não pode impedir o aplicativo de abrir:
  /// sem aviso no celular, todo o resto continua funcionando.
  static Future<void> iniciar() async {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      _iniciado = true;

      // No iPhone, aviso com o app aberto também aparece. No Android, com o
      // app aberto, as telas já se atualizam sozinhas e o sino do balcão toca.
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      FirebaseMessaging.onMessageOpenedApp.listen(_abrir);
      final inicial = await FirebaseMessaging.instance.getInitialMessage();
      if (inicial != null) {
        // Espera a primeira tela existir antes de empilhar o pedido em cima.
        WidgetsBinding.instance.addPostFrameCallback((_) => _abrir(inicial));
      }
    } catch (e) {
      debugPrint('Aviso no celular desligado: $e');
    }
  }

  /// Depois do login: pede a permissão (uma vez) e registra o aparelho.
  static Future<void> registrar() async {
    if (!_iniciado || usuarioId == null) return;
    try {
      final permissao = await FirebaseMessaging.instance.requestPermission();
      if (permissao.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _guardar(token);

      _renovacao ??= FirebaseMessaging.instance.onTokenRefresh.listen(_guardar);
    } catch (e) {
      // No simulador de iPhone não há token da Apple; em aparelho sem Google
      // Play também não. O resto do aplicativo segue.
      debugPrint('Não deu para registrar o aparelho: $e');
    }
  }

  /// Antes de sair da conta: este celular para de receber os avisos dela.
  static Future<void> esquecer() async {
    if (!_iniciado) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await banco.rpc('esquecer_aparelho', params: {'p_token': token});
      }
      await _renovacao?.cancel();
      _renovacao = null;
    } catch (_) {
      // Sem rede na hora de sair: o token fica, e o banco o troca de dono no
      // próximo login neste aparelho.
    }
  }

  static Future<void> _guardar(String token) async {
    if (usuarioId == null) return;
    await banco.rpc('registrar_aparelho', params: {
      'p_token': token,
      'p_plataforma': Platform.isIOS ? 'ios' : 'android',
    });
  }

  /// O toque no aviso. Para o cliente, abre o pedido; para o balcão, o
  /// aplicativo já abre na fila, que é onde o pedido novo está. Corrida nova
  /// leva o entregador direto às corridas, mesmo que o app estivesse no
  /// fluxo do cliente.
  static void _abrir(RemoteMessage mensagem) {
    final pedido = mensagem.data['pedido'];
    final url = mensagem.data['url'] as String? ?? '';
    if (url == '/entregas') {
      Sessao.instancia.trocarDeFluxo(Fluxo.entregador);
      return;
    }
    if (pedido is! String || !url.startsWith('/pedidos/')) return;
    if (Sessao.instancia.fluxo != Fluxo.cliente) return;

    navegador.currentState?.push(
      MaterialPageRoute(builder: (_) => TelaAcompanhar(pedidoId: pedido)),
    );
  }
}
