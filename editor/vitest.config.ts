import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    server: { deps: { inline: ['@aicayzer/inkkit'] } },
    environment: 'jsdom',
    setupFiles: ['test/setup.ts'],
  },
})
