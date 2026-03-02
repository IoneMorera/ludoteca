<script setup>
const props = defineProps({
  message: {
    type: String,
    required: true,
  },
  icon: {
    type: String,
    default: '⚠️',
  },
  retryLabel: {
    type: String,
    default: 'Reintentar',
  },
  showRetry: {
    type: Boolean,
    default: true,
  },
})

const emit = defineEmits(['retry'])
</script>

<template>
  <div class="error-state">
    <p class="error-icon">{{ props.icon }}</p>
    <p>{{ props.message }}</p>
    <button
      v-if="props.showRetry"
      class="btn btn-primary"
      type="button"
      @click="emit('retry')"
    >
      {{ props.retryLabel }}
    </button>
  </div>
</template>

<style scoped>
</style>

