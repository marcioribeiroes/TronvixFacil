"use client"

import { useEffect } from "react"

import { registrarErro } from "@/lib/registrar-erro"

/**
 * Quando ate o layout quebra. Registra o erro e da ao cliente uma saida — em
 * vez da tela branca do navegador.
 *
 * Esta pagina desenha o proprio documento e nao recebe o CSS do site, por isso
 * os estilos sao escritos aqui mesmo.
 */
export default function ErroGeral({
  error,
  retry,
}: {
  error: Error & { digest?: string }
  retry: () => void
}) {
  useEffect(() => {
    void registrarErro({
      origem: "navegador",
      mensagem: error.message,
      pilha: error.stack,
      endereco: window.location.pathname,
      contexto: { digest: error.digest, tipo: "tela-de-erro" },
    })
  }, [error])

  return (
    <html lang="pt-BR">
      <body
        style={{
          margin: 0,
          minHeight: "100dvh",
          display: "grid",
          placeItems: "center",
          fontFamily: "system-ui, sans-serif",
          background: "#fff",
          color: "#111",
          padding: 24,
          textAlign: "center",
        }}
      >
        <title>Algo deu errado</title>
        <div style={{ maxWidth: 360 }}>
          <h1 style={{ fontSize: 22, margin: "0 0 8px" }}>Algo deu errado</h1>
          <p style={{ color: "#555", margin: "0 0 20px", lineHeight: 1.5 }}>
            Já avisamos a equipe. Tente de novo — se continuar, volte daqui a pouco.
          </p>
          <button
            type="button"
            onClick={() => retry()}
            style={{
              background: "#e11d2f",
              color: "#fff",
              border: 0,
              borderRadius: 10,
              padding: "12px 20px",
              fontSize: 15,
              fontWeight: 600,
              cursor: "pointer",
            }}
          >
            Tentar de novo
          </button>
        </div>
      </body>
    </html>
  )
}
