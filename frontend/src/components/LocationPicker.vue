<script setup>
import { ref, computed, watch, onMounted } from 'vue'
import { useHabitacionesStore } from '../stores/habitaciones'
import { useMueblesStore } from '../stores/muebles'
import { useUbicacionesStore } from '../stores/ubicaciones'

const props = defineProps({
  modelValue: {
    type: [Number, String, null],
    default: '',
  },
})

const emit = defineEmits(['update:modelValue'])

const habitacionesStore = useHabitacionesStore()
const mueblesStore = useMueblesStore()
const ubicacionesStore = useUbicacionesStore()

const habitacionId = ref('')
const muebleId = ref('')

const mueblesFiltrados = computed(() => {
  if (!habitacionId.value) return mueblesStore.muebles
  return mueblesStore.muebles.filter(
    (m) =>
      m.habitacion_id === Number(habitacionId.value) ||
      m.habitacion?.id === Number(habitacionId.value),
  )
})

const ubicacionesFiltradas = computed(() => {
  if (!muebleId.value) return []
  return ubicacionesStore.ubicaciones.filter(
    (u) => u.mueble_id === Number(muebleId.value),
  )
})

function onHabitacionChange() {
  muebleId.value = ''
  emit('update:modelValue', '')
}

function onMuebleChange() {
  emit('update:modelValue', '')
}

function onUbicacionChange(event) {
  const value = event.target.value
  emit('update:modelValue', value ? Number(value) : '')
}

onMounted(async () => {
  await Promise.all([
    habitacionesStore.fetchHabitaciones(),
    mueblesStore.fetchMuebles(),
    ubicacionesStore.fetchUbicaciones(),
  ])

  if (props.modelValue) {
    const ubicacion = ubicacionesStore.ubicaciones.find(
      (u) => u.id === Number(props.modelValue),
    )
    if (ubicacion) {
      muebleId.value = ubicacion.mueble_id
      const mueble = mueblesStore.muebles.find((m) => m.id === ubicacion.mueble_id)
      if (mueble) {
        habitacionId.value = mueble.habitacion_id || mueble.habitacion?.id || ''
      }
    }
  }
})

watch(
  () => props.modelValue,
  (nuevo) => {
    if (!nuevo) {
      // si se limpia desde fuera, reseteamos solo la ubicación
      return
    }
    const ubicacion = ubicacionesStore.ubicaciones.find(
      (u) => u.id === Number(nuevo),
    )
    if (ubicacion) {
      muebleId.value = ubicacion.mueble_id
      const mueble = mueblesStore.muebles.find((m) => m.id === ubicacion.mueble_id)
      if (mueble) {
        habitacionId.value = mueble.habitacion_id || mueble.habitacion?.id || ''
      }
    }
  },
)
</script>

<template>
  <div class="form-row">
    <div class="form-group">
      <label>Habitación</label>
      <select
        v-model="habitacionId"
        class="input"
        @change="onHabitacionChange"
      >
        <option value="">Sin asignar</option>
        <option
          v-for="hab in habitacionesStore.habitaciones"
          :key="hab.id"
          :value="hab.id"
        >
          {{ hab.nombre }}
        </option>
      </select>
    </div>
    <div class="form-group">
      <label>Mueble</label>
      <select
        v-model="muebleId"
        class="input"
        :disabled="!habitacionId"
        @change="onMuebleChange"
      >
        <option value="">Sin asignar</option>
        <option
          v-for="m in mueblesFiltrados"
          :key="m.id"
          :value="m.id"
        >
          {{ m.nombre }}
        </option>
      </select>
    </div>
    <div class="form-group">
      <label>Ubicación</label>
      <select
        class="input"
        :value="modelValue"
        :disabled="!muebleId"
        @change="onUbicacionChange"
      >
        <option value="">Sin asignar</option>
        <option
          v-for="u in ubicacionesFiltradas"
          :key="u.id"
          :value="u.id"
        >
          {{ u.nombre }}
        </option>
      </select>
    </div>
  </div>
</template>

<style scoped>
</style>

