import { defineConfig } from 'vite'
import { viteSingleFile } from 'vite-plugin-singlefile'

export default defineConfig({
  base: './',
  plugins: [viteSingleFile({ deleteInlinedFiles: false })],
  build: {
    target: 'safari18',
    modulePreload: false,
    cssCodeSplit: false,
    license: { fileName: 'HOST-THIRD-PARTY-NOTICES.md' },
  },
})
