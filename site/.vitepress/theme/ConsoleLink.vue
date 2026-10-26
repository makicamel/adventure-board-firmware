<script setup lang="ts">
// A link to the console, in a new tab, optionally opening one of its samples
// (?example=01_light.rb). A plain Markdown link with {target="_blank"} is left
// alone by VitePress and loses the site's base, which on GitHub Pages is a 404.
//
// The console sits beside the guide (console/) unless VITE_CONSOLE_URL says
// where it is, for when it is published as a site of its own.
import { computed } from 'vue'
import { withBase } from 'vitepress'

const props = defineProps<{ example?: string }>()

const href = computed(() => {
  const url = import.meta.env.VITE_CONSOLE_URL || withBase('/console/')
  return props.example ? `${url}?example=${encodeURIComponent(props.example)}` : url
})
</script>

<template>
  <a :href="href" target="_blank" rel="noopener"><slot>▶ コンソールで開く</slot></a>
</template>
