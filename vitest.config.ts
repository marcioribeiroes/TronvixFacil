import { defineConfig } from "vitest/config"

export default defineConfig({
  // O Vite ja resolve os caminhos do tsconfig ("@/..") nativamente; nao ha
  // plugin envolvido.
  resolve: { tsconfigPaths: true },
  test: {
    environment: "node",
    include: ["src/**/*.test.ts", "src/**/*.test.tsx"],
  },
})
