import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// The API base is normally read from VITE_API_BASE (see .env), so the app can call
// the FastAPI gateway directly (CORS is enabled backend-side). A dev proxy for
// `/api` is also provided as a fallback for same-origin calls.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: 'http://127.0.0.1:8000',
        changeOrigin: true,
        rewrite: (p) => p.replace(/^\/api/, ''),
      },
    },
  },
})
