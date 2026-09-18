/// Configuração que vem de fora do código.
///
/// No celular não existe `.env`: o aplicativo é compilado e instalado, e o que
/// ele sabe do mundo entra na compilação. Por isso `--dart-define`, e não
/// leitura de arquivo — uma chave lida de arquivo num app instalado seria
/// apenas um arquivo a mais para alguém abrir.
///
/// ```sh
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=...
/// ```
///
/// A chave anônima é pública por definição — quem protege os dados é a RLS do
/// Postgres, não o segredo da chave. A `service_role` nunca entra aqui.
///
/// **Tudo aqui é `const`.** É o que permite trocar a cor da marca sem tocar em
/// nenhuma tela: `Color` continua sendo constante de compilação, e as centenas
/// de `const TextStyle(color: Cores.marca)` espalhadas pelo aplicativo seguem
/// válidas.
library;

/// O aplicativo mostra a praça inteira ou uma loja só?
enum ModoDoAplicativo {
  /// Vitrine com todos os estabelecimentos do servidor.
  multi,

  /// Uma loja só. Sem vitrine, sem escolher onde pedir — o aplicativo é *do*
  /// restaurante, e abre direto no cardápio dele.
  unico,
}

class Ambiente {
  static const urlSupabase = String.fromEnvironment('SUPABASE_URL');
  static const chaveAnonima = String.fromEnvironment('SUPABASE_ANON_KEY');

  static const nomeDaMarca = String.fromEnvironment(
    'NOME_DA_MARCA',
    defaultValue: 'Tronvix Fácil',
  );

  /// `multi` (padrão) ou `unique`.
  static const _modo = String.fromEnvironment('MODO', defaultValue: 'multi');

  /// O `slug` do estabelecimento, quando o modo é único. É a coluna
  /// `restaurants.slug` — legível, estável, e a mesma que a web usa na URL.
  static const estabelecimento = String.fromEnvironment('ESTABELECIMENTO');

  /// As cores, em ARGB. `0xFFE11D2F` é o vermelho do Tronvix Fácil.
  ///
  /// Quem revende o sistema troca estes três números e tem a própria marca, sem
  /// recompilar nada além do aplicativo.
  static const corDaMarca =
      int.fromEnvironment('COR_DA_MARCA', defaultValue: 0xFFE11D2F);
  static const corDaMarcaEscura =
      int.fromEnvironment('COR_DA_MARCA_ESCURA', defaultValue: 0xFFB3121F);
  static const corDeRealce =
      int.fromEnvironment('COR_DE_REALCE', defaultValue: 0xFFFEF2F3);

  static ModoDoAplicativo get modo => _modo == 'unique' || _modo == 'unico'
      ? ModoDoAplicativo.unico
      : ModoDoAplicativo.multi;

  static bool get unico => modo == ModoDoAplicativo.unico;

  /// O aplicativo está apontado para algum Supabase?
  ///
  /// Existe pelo mesmo motivo do `supabaseConfigurado()` da web: sem isso, quem
  /// compila sem as chaves recebe um "Invalid API key" no meio da primeira
  /// tela, em vez de uma instrução de como configurar.
  static bool get configurado =>
      urlSupabase.isNotEmpty && chaveAnonima.isNotEmpty;

  /// O modo único sem estabelecimento configurado é um aplicativo sem
  /// cardápio. Vale checar na subida, não na primeira tela em branco.
  static bool get coerente => !unico || estabelecimento.isNotEmpty;

  static const instrucao =
      'Compile com --dart-define=SUPABASE_URL=... e '
      '--dart-define=SUPABASE_ANON_KEY=..., ou use o script celular/rodar.sh, '
      'que lê essas chaves do .env.local do projeto.';

  static const instrucaoDoModoUnico =
      'O modo único precisa saber de qual estabelecimento ele é. '
      'Compile com --dart-define=ESTABELECIMENTO=<slug>, ou preencha '
      'CELULAR_ESTABELECIMENTO no .env.local.';
}
