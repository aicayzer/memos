import { readFileSync } from 'node:fs'
import { defineConfig } from 'vitest/config'

export default defineConfig({
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
  test: {
    server: { deps: { inline: ['@aicayzer/inkkit'] } },
    environment: 'jsdom',
    setupFiles: ['test/setup.ts'],
  },
})
