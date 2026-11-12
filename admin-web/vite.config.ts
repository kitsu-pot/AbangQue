import { defineConfig, loadEnv } from "vite";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "");
  return {
    plugins: [tailwindcss()],
    server: {
      host: "127.0.0.1",
      port: 5173,
      strictPort: true,
      proxy: {
        "/api/admin": {
          target: env.ADMIN_API_PROXY_TARGET || "http://127.0.0.1:3000",
          changeOrigin: false,
        },
      },
    },
    preview: { port: 5173, strictPort: true },
  };
});
