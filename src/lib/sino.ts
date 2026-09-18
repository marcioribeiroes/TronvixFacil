/**
 * O sino do balcao.
 *
 * Som de sino de recepcao, sintetizado na hora: um golpe curto e brilhante que
 * decai devagar. Nada de arquivo baixado — som de terceiro tem licenca, e uma
 * licenca esquecida num produto revendido a restaurantes e um problema que
 * aparece tarde.
 *
 * Por que sino e nao bipe: dois bipes de oscilador se perdem no barulho de uma
 * cozinha, e soam como notificacao de celular — o cerebro ja aprendeu a
 * ignorar. Sino de recepcao e o som que significa "tem alguem esperando".
 */

/**
 * As parciais de um sino: frequencias que NAO sao multiplos inteiros da
 * fundamental. E isso que distingue sino de flauta — num sino os harmonicos
 * sao inarmonicos, e e dai que vem o brilho metalico.
 */
const PARCIAIS = [
  { razao: 1, volume: 1, decaimento: 1.6 },
  { razao: 2.76, volume: 0.62, decaimento: 1.1 },
  { razao: 5.4, volume: 0.38, decaimento: 0.7 },
  { razao: 8.93, volume: 0.22, decaimento: 0.45 },
]

let contexto: AudioContext | null = null

/** Um contexto so, reaproveitado: cada `new AudioContext` come um recurso. */
function pegarContexto(): AudioContext | null {
  try {
    if (!contexto) {
      const Classe =
        window.AudioContext ??
        (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext
      if (!Classe) return null
      contexto = new Classe()
    }
    // O navegador suspende o contexto quando a aba fica de lado; sem retomar,
    // o sino toca em silencio e ninguem entende por que.
    if (contexto.state === "suspended") void contexto.resume()
    return contexto
  } catch {
    return null
  }
}

/** Um golpe. `quando` e em segundos a partir de agora. */
function golpe(ctx: AudioContext, quando: number, fundamental: number, forca: number) {
  const inicio = ctx.currentTime + quando

  for (const p of PARCIAIS) {
    const oscilador = ctx.createOscillator()
    const volume = ctx.createGain()

    oscilador.type = "sine"
    oscilador.frequency.value = fundamental * p.razao

    // Ataque quase instantaneo e queda exponencial: e a forma de onda de algo
    // que foi golpeado, e nao de algo que foi ligado.
    volume.gain.setValueAtTime(0.0001, inicio)
    volume.gain.exponentialRampToValueAtTime(p.volume * forca, inicio + 0.004)
    volume.gain.exponentialRampToValueAtTime(0.0001, inicio + p.decaimento)

    oscilador.connect(volume).connect(ctx.destination)
    oscilador.start(inicio)
    oscilador.stop(inicio + p.decaimento + 0.05)
  }
}

/**
 * Toca o sino.
 *
 * Dois golpes, como numa campainha de recepcao — um golpe so passa por acaso;
 * dois sao um chamado.
 */
export function tocarSino(forca = 0.28) {
  const ctx = pegarContexto()
  if (!ctx) return

  golpe(ctx, 0, 1046.5, forca) // dó6
  golpe(ctx, 0.17, 1318.5, forca * 0.9) // mi6
}

/**
 * Destrava o som.
 *
 * O navegador so deixa tocar depois de a pessoa ter interagido com a pagina —
 * protecao contra paginas que gritam sozinhas, e nao ha como contornar. Esta
 * funcao e chamada no primeiro clique, e o que ela faz e criar e retomar o
 * contexto enquanto o gesto ainda vale.
 */
export function destravarSom(): boolean {
  const ctx = pegarContexto()
  return ctx?.state === "running"
}
