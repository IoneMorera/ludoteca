<script setup>
const props = defineProps({
  value: {
    type: String,
    required: true,
  },
  type: {
    type: String,
    default: 'juego', // 'juego' | 'prestamo'
  },
})

const clasesJuego = {
  disponible: 'badge-success',
  prestado: 'badge-warning',
  reparacion: 'badge-info',
  baja: 'badge-danger',
}

const clasesPrestamo = {
  activo: 'badge-warning',
  devuelto: 'badge-success',
  retrasado: 'badge-danger',
}

function badgeClass() {
  if (props.type === 'prestamo') {
    return clasesPrestamo[props.value] || ''
  }
  return clasesJuego[props.value] || ''
}
</script>

<template>
  <span class="badge" :class="badgeClass()">
    {{ props.value }}
  </span>
</template>

<style scoped>
</style>

