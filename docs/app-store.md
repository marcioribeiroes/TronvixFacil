# Publicar o Tronvix Fácil na App Store

O que a Apple pede, e o que já está pronto no repositório. O que depende de
você está marcado com **você**.

A ordem importa: a Apple recusa a ficha sem URL de privacidade, e a URL de
privacidade só existe depois do deploy da web. Publicar na loja é a última
coisa, não a primeira.

---

## 1. Antes de tudo (**você**)

- **Apple Developer Program** ativo — US$ 99 por ano. Conta gratuita não
  publica, só instala no próprio aparelho.
- O time já configurado no projeto é `5V9K79AGTR`
  (`celular/ios/Runner.xcodeproj`). Se a conta que vai publicar for outra, este
  número muda.
- Identificador do app: `br.com.tronvix.tronvixFacil`.

---

## 2. A chave da API (**você**, 3 minutos)

App Store Connect → **Usuários e Acesso** → **Integrações** → **Chaves da API**
→ gerar uma chave com a função **App Manager**.

O arquivo `.p8` só pode ser baixado **uma vez**. Guarde-o fora do repositório,
como a chave de upload do Android — ver `docs/google-play.md`.

```sh
export ASC_KEY_ID=XXXXXXXXXX
export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
export ASC_KEY_P8=~/.chaves/AuthKey_XXXXXXXXXX.p8
```

---

## 3. Enviar

```sh
cd celular/ios
fastlane conferir   # valida a chave e diz se a Apple já conhece o app
fastlane criar      # registra o app, se ainda não existir
fastlane beta       # compila, assina e sobe para o TestFlight
fastlane loja       # sobe a ficha: textos e capturas
```

Nada é enviado para revisão por comando. O último clique é humano.

A ficha vive em `celular/ios/fastlane/metadata/pt-BR/` e as capturas em
`celular/ios/fastlane/screenshots/pt-BR/`, escritas por
`flutter test tool/gerar_capturas.dart` no tamanho de 6,9 polegadas
(1320×2868) que a Apple exige hoje. Medida errada, envio recusado.

Antes de rodar `fastlane loja`, preencha em `fastlane/Deliverfile`:

```ruby
privacy_url("https://SEU-DOMINIO/privacidade")
support_url("https://SEU-DOMINIO")
```

---

## 4. Privacidade

Três lugares dizem a mesma coisa, e precisam mudar no mesmo dia:

| Onde | O quê |
| --- | --- |
| `src/app/privacidade/page.tsx` | o texto que a pessoa lê |
| `celular/ios/Runner/PrivacyInfo.xcprivacy` | o manifesto que a Apple lê |
| App Store Connect → Privacidade do app | o formulário (**você**, no site) |

No formulário, o que marcar:

- **Rastreamento**: não. Não há SDK de anúncio nem analytics de terceiro.
- Coletados e **vinculados à identidade**, todos para "Funcionalidade do app":
  nome, e-mail, telefone, endereço, localização precisa, histórico de compras,
  ID de usuário.
- **Não** marque: fotos (a câmera só lê o QR e nada é enviado), contatos,
  informações financeiras (não guardamos cartão), saúde, publicidade.

E o app precisa da **URL de exclusão de conta**: `https://SEU-DOMINIO/excluir-conta`.
A Apple exige o mesmo que a Google — quem cria conta pelo app precisa poder
apagá-la de dentro dele, e o caminho está em Conta → Apagar minha conta.

---

## 5. Revisão: o que costuma travar

- **Conta de teste.** O revisor precisa entrar. Em "Informações da revisão",
  deixe um e-mail e senha de um cliente de verdade do ambiente de produção, e
  escreva na observação que o aplicativo abre em modo delivery e que o QR da
  mesa também aceita **código digitado** — o revisor não tem uma mesa com
  etiqueta na frente dele.
- **Permissão de câmera e de localização.** Os textos que aparecem no pedido de
  permissão estão em `celular/ios/Runner/Info.plist` e precisam dizer para quê,
  não só "o app usa a câmera". Já dizem.
- **Login social obrigatório**: não se aplica — não usamos login de terceiro,
  então a Apple não exige "Entrar com a Apple".
- **Conteúdo gerado por terceiro**: o cardápio e as fotos são do restaurante. Se
  a Apple perguntar, a moderação é nossa: loja entra como `pending` e um
  administrador aprova.

---

## 6. Idade

**17+** é o caminho seguro se algum cardápio tiver bebida alcoólica ("uso
frequente/intenso de álcool" não; "referências a álcool", sim). Hoje a semente
não tem bebida alcoólica e **12+** basta. A primeira churrascaria que cadastrar
cerveja muda isso, e a classificação precisa ser refeita nas duas lojas.
