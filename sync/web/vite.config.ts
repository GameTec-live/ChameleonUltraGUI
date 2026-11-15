import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

export default defineConfig({
  // Relative URLs: the page also works when the server sits under a path prefix.
  base: "./",
  plugins: [react(), tailwindcss()],
  // `bun run dev` talks to a server on the default port.
  server: { proxy: { "/v1": "http://127.0.0.1:8787" } },
});
