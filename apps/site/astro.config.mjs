import { defineConfig } from 'astro/config'
import react from '@astrojs/react'
import mdx from '@astrojs/mdx'

export default defineConfig({
  site: 'https://lattices.dev',
  integrations: [
    react(),
    mdx(),
  ],
  vite: {
    ssr: {
      noExternal: [],
    },
  },
})
