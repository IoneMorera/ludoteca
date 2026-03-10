<script setup>
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import AppNavbar from './components/AppNavbar.vue'

const route = useRoute()
const isAuthPage = computed(() => route.meta.guest === true)
</script>

<template>
  <div v-if="isAuthPage">
    <router-view />
  </div>
  <div v-else class="app-layout">
    <AppNavbar />
    <main class="main-content">
      <router-view />
    </main>
  </div>
</template>

<style scoped>
</style>
