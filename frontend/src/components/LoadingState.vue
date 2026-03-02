<script setup>
const props = defineProps({
  text: {
    type: String,
    default: 'Cargando...',
  },
  spinner: {
    type: Boolean,
    default: false,
  },
  hint: {
    type: String,
    default: '',
  },
})
</script>

<template>
  <div class="loading">
    <div v-if="props.spinner" class="spinner"></div>
    <p>{{ props.text }}</p>
    <p v-if="props.hint" class="loading-hint">
      {{ props.hint }}
    </p>
  </div>
</template>

<style scoped>
.spinner {
  width: 40px;
  height: 40px;
  border: 4px solid #e0e0e0;
  border-top-color: var(--primary);
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
  margin: 0 auto 1rem;
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}

.loading-hint {
  font-size: 0.8rem;
  color: var(--text-muted);
  margin-top: 0.5rem;
}
</style>


