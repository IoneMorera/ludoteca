<script setup>
const props = defineProps({
  items: {
    type: Array,
    required: true,
  },
})
</script>

<template>
  <div class="cards-grid">
    <slot
      v-for="item in props.items"
      :key="item.id"
      :item="item"
    />
  </div>
</template>

<style scoped>
</style>

