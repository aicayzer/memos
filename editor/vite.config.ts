import { defineConfig } from 'vite'
import { viteSingleFile } from 'vite-plugin-singlefile'

export default defineConfig({
  base: './',
  plugins: [viteSingleFile()],
  build: {
    target: 'safari18',
    modulePreload: false,
    cssCodeSplit: false,
  },
})
