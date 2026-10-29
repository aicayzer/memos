import { readFileSync } from 'node:fs'
import { defineConfig } from 'vite'
import { viteSingleFile } from 'vite-plugin-singlefile'

export default defineConfig({
  base: './',
  define: {
    __INKKIT_VERSION__: JSON.stringify(
      JSON.parse(
        readFileSync(
          new URL('../package.json', import.meta.resolve('@aicayzer/inkkit/core')),
          'utf8',
        ),
      ).version,
    ),
  },
  plugins: [viteSingleFile({ deleteInlinedFiles: false })],
  build: {
    target: 'safari18',
    modulePreload: false,
    cssCodeSplit: false,
    license: { fileName: 'HOST-THIRD-PARTY-NOTICES.md' },
  },
})
