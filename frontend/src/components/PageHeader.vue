<script setup>
const props = defineProps({
  title: {
    type: String,
    required: true,
  },
  subtitle: {
    type: String,
    default: '',
  },
})
</script>

<template>
  <div class="page-header">
    <div>
      <h1 class="page-title">{{ props.title }}</h1>
      <p v-if="props.subtitle" class="page-subtitle">
        {{ props.subtitle }}
      </p>
    </div>
    <div class="page-header-actions">
      <slot name="actions" />
    </div>
  </div>
</template>

<style scoped>
.page-header-actions {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}
</style>

