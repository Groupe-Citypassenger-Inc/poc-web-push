import { defineConfig } from 'vite';
import dotenv from 'dotenv';
dotenv.config();

export default defineConfig({
  base: './',
  build: {
    assetsDir: './',
  },
  define: {
    __APP_PUSH_PUBLIC_KEY__: `'${process.env.PUBLIC_KEY}'`
  },
  server: {
    proxy: {
      '/wps': { target: 'http://127.0.0.1:3000', secure: false },
    },
  }
});