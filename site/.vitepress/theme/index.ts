import DefaultTheme from 'vitepress/theme'
import type { Theme } from 'vitepress'
import ConsoleLink from './ConsoleLink.vue'
import './style.css'

export default {
  extends: DefaultTheme,
  enhanceApp({ app }) {
    app.component('ConsoleLink', ConsoleLink)
  }
} satisfies Theme
