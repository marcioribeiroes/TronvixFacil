import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'ambiente.dart';
import 'cliente/inicio.dart';
import 'comum/sons.dart';
import 'comum/widgets.dart';
import 'dados/carrinho.dart';
import 'dados/supabase.dart';
import 'entregador/inicio.dart';
import 'restaurante/inicio.dart';
import 'sessao.dart';
import 'tema.dart';
import 'telas/entrar.dart';

/// Preparo que roda antes de qualquer tela.
///
/// Separado de `main` porque o teste de widget monta o aplicativo direto e
/// precisa passar pelo mesmo caminho — sem `initializeDateFormatting`, toda
/// tela que formata data estoura com `LocaleDataException` no teste estando
/// certa no aplicativo.
Future<void> prepararApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  await iniciarSupabase();
}

void main() async {
  await prepararApp();
  runApp(const AppTronvixFacil());
}

class AppTronvixFacil extends StatelessWidget {
  const AppTronvixFacil({super.key});

  /// Exposto para que um teste possa montar uma tela sozinha com o mesmo tema
  /// do aplicativo — sem isso, a captura sairia com o tema padrão do Flutter.
  static final ThemeData tema = temaClaro();

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: Ambiente.nomeDaMarca,
        debugShowCheckedModeBanner: false,
        theme: tema,
        home: const Porta(),
      );
}

/// A porta de entrada: decide o que mostrar e para quem.
class Porta extends StatefulWidget {
  const Porta({super.key});

  @override
  State<Porta> createState() => _PortaState();
}

class _PortaState extends State<Porta> {
  bool _pronto = false;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    if (!Ambiente.configurado) {
      setState(() => _pronto = true);
      return;
    }

    // Uma sessão gravada no aparelho já vem restaurada pelo SDK; o que falta é
    // saber quem é a pessoa no banco, que é o que decide o fluxo.
    await Sessao.instancia.carregar();
    if (Sessao.instancia.autenticado) await Carrinho.instancia.carregar();

    autenticacao.onAuthStateChange.listen((evento) async {
      await Sessao.instancia.carregar();
      if (Sessao.instancia.autenticado) {
        await Carrinho.instancia.carregar();
      } else {
        Carrinho.instancia.esquecer();
      }
    });

    if (mounted) setState(() => _pronto = true);

    // O sino de abertura. Só depois de a primeira tela estar pronta: tocar
    // enquanto o aplicativo ainda carrega soa como erro, não como boas-vindas.
    unawaited(Sons.tocar(Toque.cheio));
  }

  @override
  Widget build(BuildContext context) {
    if (!Ambiente.configurado) return const _SemConfiguracao();
    if (!_pronto) {
      return const Scaffold(body: Carregando(mensagem: 'Abrindo…'));
    }

    return ListenableBuilder(
      listenable: Sessao.instancia,
      builder: (context, _) {
        final sessao = Sessao.instancia;

        // A vitrine abre sem login, de propósito: exigir cadastro para só
        // olhar o cardápio é o jeito mais barato de perder um cliente com
        // fome. A conta é pedida quando ele monta o pedido.
        if (!sessao.autenticado) return const InicioDoCliente();

        return switch (sessao.fluxo) {
          Fluxo.cliente => const InicioDoCliente(),
          Fluxo.restaurante => const InicioDoRestaurante(),
          Fluxo.entregador => const InicioDoEntregador(),
        };
      },
    );
  }
}

/// Compilado sem apontar para nenhum Supabase.
///
/// Mesma escolha da web: dizer o que falta, em vez de quebrar com "Invalid API
/// key" no meio da primeira tela.
class _SemConfiguracao extends StatelessWidget {
  const _SemConfiguracao();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Vazio(
          icone: Icons.settings_outlined,
          titulo: 'Falta apontar para o Supabase',
          detalhe: Ambiente.instrucao,
        ),
      );
}

/// Atalho usado pelas telas que exigem conta: leva a [TelaEntrar] e devolve
/// true se a pessoa entrou.
Future<bool> exigirConta(BuildContext context) async {
  if (Sessao.instancia.autenticado) return true;
  final entrou = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => const TelaEntrar()),
  );
  return entrou ?? false;
}
