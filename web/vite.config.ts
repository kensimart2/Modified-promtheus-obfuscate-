import tailwindcss from "@tailwindcss/vite"
import react from "@vitejs/plugin-react"
import { defineConfig } from "vite"

import { prometheusLuaPlugin } from "./src/vite/prometheusLuaPlugin"

export default defineConfig(() => {
  const docsPathRegex = /^\/(?:Prometheus\/)?docs\/?$/
  const rewriteDocsRequest = (url: string) => {
    const [pathname, search = ""] = url.split("?", 2)
    if (!pathname || !docsPathRegex.test(pathname)) {
      return url
    }
    return `/docs/index.html${search ? `?${search}` : ""}`
  }

  return {
    // In AI Studio, the application runs at the root of the domain, so we use "/" as base.
    base: "/",
    server: {
      host: "0.0.0.0",
      port: 3000,
      allowedHosts: true
    },
    preview: {
      host: "0.0.0.0",
      port: 3000,
      allowedHosts: true
    },
    plugins: [
      {
        name: "serve-docs-index-directly",
        configureServer(server) {
          server.middlewares.use((req, _res, next) => {
            if (req.url) {
              req.url = rewriteDocsRequest(req.url)
            }
            next()
          })
        },
        configurePreviewServer(server) {
          server.middlewares.use((req, _res, next) => {
            if (req.url) {
              req.url = rewriteDocsRequest(req.url)
            }
            next()
          })
        },
      },
      react(),
      tailwindcss(),
      prometheusLuaPlugin(),
    ],
    worker: {
      format: "es",
      plugins: () => [prometheusLuaPlugin()],
    },
    resolve: {
      alias: {
        "@": new URL("./src", import.meta.url).pathname,
      },
    },
    optimizeDeps: {
      exclude: ["wasmoon"],
    },
    test: {
      environment: "node",
      setupFiles: "./src/test/setup.ts",
      exclude: ["src/e2e/**", "node_modules/**", "dist/**"],
    },
  }
})
