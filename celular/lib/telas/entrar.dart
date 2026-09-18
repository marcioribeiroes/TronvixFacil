/// Entrar e criar conta.
///
/// Uma tela só para as duas coisas: alternar entre "entrar" e "criar conta" é
/// um toque, não uma navegação. Quem chegou aqui no meio de um pedido tem
/// pressa.
library;

import 'package:flutter/material.dart';

import '../ambiente.dart';
import '../comum/fundo_da_marca.dart';
import '../comum/widgets.dart';
import '../sessao.dart';
import '../tema.dart';

class TelaEntrar extends StatefulWidget {
  const TelaEntrar({super.key});

  @override
  State<TelaEntrar> createState() => _TelaEntrarState();
}

class _TelaEntrarState extends State<TelaEntrar> {
  final _formulario = GlobalKey<FormState>();
  final _nome = TextEditingController();
  final _email = TextEditingController();
  final _senha = TextEditingController();
  final _telefone = TextEditingController();

  bool _criandoConta = false;
  bool _ocupado = false;
  bool _senhaVisivel = false;

  @override
  void dispose() {
    _nome.dispose();
    _email.dispose();
    _senha.dispose();
    _telefone.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (!_formulario.currentState!.validate()) return;
    setState(() => _ocupado = true);

    try {
      if (_criandoConta) {
        await Sessao.instancia.criarConta(
          nome: _nome.text,
          email: _email.text,
          senha: _senha.text,
          telefone: _telefone.text,
        );
      } else {
        await Sessao.instancia.entrar(_email.text, _senha.text);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) avisar(context, e.toString(), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _recuperar() async {
    if (_email.text.trim().isEmpty) {
      avisar(context, 'Escreva seu e-mail primeiro.', erro: true);
      return;
    }
    try {
      await Sessao.instancia.recuperarSenha(_email.text);
      if (mounted) {
        avisar(context, 'Enviamos um link de recuperação para ${_email.text}.');
      }
    } catch (e) {
      if (mounted) avisar(context, e.toString(), erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final alturaDaTela = MediaQuery.of(context).size.height;
    final tecladoAberto = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: Cores.fundo,
      body: Column(
        children: [
          // A faixa da marca. Encolhe quando o teclado sobe: o campo que a
          // pessoa está preenchendo importa mais que a apresentação.
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            height: tecladoAberto ? 0 : alturaDaTela * 0.38,
            child: FundoDaMarca(
              filho: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: AssinaturaDaMarca(
                              nome: Ambiente.nomeDaMarca,
                              legenda: Ambiente.unico ? 'Pedidos' : 'Delivery',
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(Icons.close, color: Colors.white54),
                            tooltip: 'Fechar',
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        _criandoConta
                            ? 'CRIE SUA CONTA'
                            : 'BEM-VINDO DE VOLTA',
                        style: TextStyle(
                          color: Cores.marca,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 3.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _criandoConta
                            ? 'Seus dados ficam\ncom você.'
                            : 'Que bom ver\nvocê de novo.',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 27,
                          fontWeight: FontWeight.w700,
                          height: 1.08,
                          letterSpacing: -0.9,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  20, 24, 20, 24 + MediaQuery.of(context).padding.bottom),
              child: Form(
                key: _formulario,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  Text(
                    _criandoConta
                        ? 'Precisamos do nome para o restaurante saber quem pediu, e do telefone para o entregador achar você.'
                        : 'Entre para acompanhar seus pedidos e usar seus endereços salvos.',
                    style: const TextStyle(color: Cores.textoSuave, height: 1.4),
                  ),
                  const SizedBox(height: 22),
                  if (_criandoConta) ...[
                    TextFormField(
                      controller: _nome,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                          labelText: 'Nome completo',
                          prefixIcon: Icon(Icons.person_outline)),
                      validator: (v) => (v == null || v.trim().length < 3)
                          ? 'Escreva seu nome'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _telefone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                          labelText: 'Celular com DDD',
                          prefixIcon: Icon(Icons.phone_outlined)),
                      validator: (v) {
                        final d = (v ?? '').replaceAll(RegExp(r'\D'), '');
                        // O banco exige de 10 a 13 dígitos no perfil; recusar
                        // aqui poupa a pessoa de descobrir isso depois de
                        // preencher o resto.
                        if (d.isEmpty) return 'Informe um celular';
                        if (d.length < 10) return 'Faltam dígitos';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                        labelText: 'E-mail',
                        prefixIcon: Icon(Icons.mail_outline)),
                    validator: (v) => (v == null || !v.contains('@'))
                        ? 'E-mail inválido'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _senha,
                    obscureText: !_senhaVisivel,
                    decoration: InputDecoration(
                      labelText: 'Senha',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_senhaVisivel
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        onPressed: () =>
                            setState(() => _senhaVisivel = !_senhaVisivel),
                      ),
                    ),
                    validator: (v) => (v == null || v.length < 6)
                        ? 'Ao menos 6 caracteres'
                        : null,
                  ),
                  if (!_criandoConta)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _ocupado ? null : _recuperar,
                        child: const Text('Esqueci a senha'),
                      ),
                    ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _ocupado ? null : _enviar,
                    child: _ocupado
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.4, color: Colors.white))
                        : Text(_criandoConta ? 'Criar conta' : 'Entrar'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _ocupado
                        ? null
                        : () => setState(() => _criandoConta = !_criandoConta),
                    child: Text(_criandoConta
                        ? 'Já tenho conta'
                        : 'Criar uma conta'),
                  ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
