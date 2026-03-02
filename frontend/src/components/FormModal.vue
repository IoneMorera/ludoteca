<script setup>
const props = defineProps({
  title: {
    type: String,
    required: true,
  },
  visible: {
    type: Boolean,
    required: true,
  },
})

const emit = defineEmits(['close'])

function onOverlayClick() {
  emit('close')
}
</script>

<template>
  <div v-if="props.visible" class="modal-overlay" @click.self="onOverlayClick">
    <div class="modal">
      <h2>{{ props.title }}</h2>
      <slot />
    </div>
  </div>
</template>

<style scoped>
</style>

