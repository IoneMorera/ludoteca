<script setup>
const props = defineProps({
  text: {
    type: String,
    default: 'No hay datos.',
  },
})
</script>

<template>
  <div class="empty">
    {{ props.text }}
  </div>
</template>

<style scoped>
</style>

