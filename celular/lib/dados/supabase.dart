/// O cliente do Supabase, num lugar só.
///
/// Nenhuma tela chama `Supabase.instance` direto: passa por aqui. A razão é
/// poder trocar o cliente no teste, e ter um ponto único onde o erro do
/// PostgREST vira mensagem em português — o cliente não precisa ler
/// "new row violates row-level security policy".
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../ambiente.dart';

export 'package:supabase_flutter/supabase_flutter.dart'
    show
        PostgrestException,
        AuthException,
        RealtimeChannel,
        PostgresChangeEvent,
        PostgresChangeFilter,
        PostgresChangeFilterType,
        PostgresChangePayload;

Future<void> iniciarSupabase() async {
  if (!Ambiente.configurado) return;
  await Supabase.initialize(
    url: Ambiente.urlSupabase,
    // O parâmetro se chama `publishableKey` nas versões novas do SDK; o valor
    // continua sendo a mesma chave pública que a web usa em
    // NEXT_PUBLIC_SUPABASE_ANON_KEY.
    publishableKey: Ambiente.chaveAnonima,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );
}

SupabaseClient get banco => Supabase.instance.client;

GoTrueClient get autenticacao => Supabase.instance.client.auth;

String? get usuarioId => Supabase.instance.client.auth.currentUser?.id;

/// Erro que já vem pronto para a tela.
///
/// Toda chamada ao banco passa por [executar]. Sem isso, cada tela acabaria
/// inventando o seu próprio jeito de traduzir a mesma falha — e falhas de RLS
/// são as que mais aparecem num sistema onde a autorização mora no banco.
class ErroDeDados implements Exception {
  ErroDeDados(this.mensagem, {this.original});
  final String mensagem;
  final Object? original;

  @override
  String toString() => mensagem;
}

Future<T> executar<T>(Future<T> Function() acao) async {
  try {
    return await acao();
  } on PostgrestException catch (e) {
    throw ErroDeDados(_traduzir(e), original: e);
  } on AuthException catch (e) {
    throw ErroDeDados(_traduzirAuth(e), original: e);
  }
}

String _traduzir(PostgrestException e) {
  final m = e.message;

  // A RLS recusou. Para quem está na tela isso quase nunca significa "erro":
  // significa que aquilo não é dele, ou que o papel mudou.
  if (e.code == '42501' || m.contains('row-level security')) {
    return 'Você não tem permissão para isso. Se acabou de mudar de conta, entre de novo.';
  }
  // Mensagem escrita à mão num gatilho ou em fechar_pedido — "O pedido minimo
  // deste estabelecimento e R\$ 20,00", "X saiu do cardapio". Essas são melhores
  // que qualquer coisa que este arquivo inventaria, e passam inteiras.
  //
  // O jeito de reconhecê-las: o Postgres escreve as dele em inglês e sempre
  // citando a trava ("violates check constraint \"...\""). O que não parece
  // mensagem do Postgres foi alguém que escreveu pensando em quem lê.
  final doPostgres = m.contains('violates') ||
      m.contains('constraint') ||
      m.contains('duplicate key') ||
      m.contains('null value in column') ||
      m.contains('invalid input syntax');

  if (m.startsWith('Transicao de status invalida')) {
    return 'Esse passo não é possível a partir da situação atual do pedido.';
  }
  if (m.contains('nao podem ser alterados apos o fechamento')) {
    return 'Os valores de um pedido fechado não podem ser alterados.';
  }
  if (m.contains('Pedido de retirada nao sai para entrega')) {
    return 'Pedido de retirada não sai para entrega.';
  }
  if (e.code == '23505') {
    return 'Isso já existe.';
  }
  if (!doPostgres && m.trim().isNotEmpty) return m;
  if (e.code == '23514' || m.contains('violates check constraint')) {
    return 'O banco recusou esses valores. Confira os campos e tente de novo.';
  }
  if (e.code == 'PGRST116') {
    return 'Não encontrado.';
  }
  return m;
}

String _traduzirAuth(AuthException e) {
  final m = e.message.toLowerCase();
  if (m.contains('invalid login credentials')) {
    return 'E-mail ou senha não conferem.';
  }
  if (m.contains('email not confirmed')) {
    return 'Confirme seu e-mail antes de entrar.';
  }
  if (m.contains('user already registered')) {
    return 'Já existe uma conta com esse e-mail.';
  }
  if (m.contains('password should be at least')) {
    return 'A senha precisa ter ao menos 6 caracteres.';
  }
  if (m.contains('rate limit') || m.contains('too many')) {
    return 'Muitas tentativas. Espere um instante e tente de novo.';
  }
  return e.message;
}
