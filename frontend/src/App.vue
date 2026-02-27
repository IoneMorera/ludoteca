<script setup>
import AppNavbar from './components/AppNavbar.vue'
</script>

<template>
  <div class="app-layout">
    <AppNavbar />
    <main class="main-content">
      <router-view />
    </main>
  </div>
</template>

<style scoped>
.app-layout {
  display: flex;
  min-height: 100vh;
}

.main-content {
  flex: 1;
  margin-left: 260px;
  padding: 2rem;
  background-color: #f5f7fa;
}

@media (max-width: 768px) {
  .main-content {
    margin-left: 0;
    padding: 1rem;
    padding-top: 4rem;
  }
}
</style>
