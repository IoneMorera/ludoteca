<script setup>
import { ref, onMounted, computed } from 'vue'
import { useUbicacionesStore } from '../stores/ubicaciones'
import { useHabitacionesStore } from '../stores/habitaciones'
import { useMueblesStore } from '../stores/muebles'
import PageHeader from '../components/PageHeader.vue'
import FilterBar from '../components/FilterBar.vue'
import LoadingState from '../components/LoadingState.vue'
import EmptyState from '../components/EmptyState.vue'
import FormModal from '../components/FormModal.vue'

const ubicacionesStore = useUbicacionesStore()
const habitacionesStore = useHabitacionesStore()
const mueblesStore = useMueblesStore()
const habitacionSeleccionada = ref('')
const muebleSeleccionado = ref('')
const mostrarFormulario = ref(false)

const form = ref({
  habitacion_id: '',
  mueble_id: '',
  nombre: '',
})

const ubicacionesFiltradas = computed(() => {
  return ubicacionesStore.ubicaciones.filter((u) => {
    const hId = u.mueble?.habitacion?.id
    const mId = u.mueble?.id
    if (habitacionSeleccionada.value && hId !== Number(habitacionSeleccionada.value)) return false
    if (muebleSeleccionado.value && mId !== Number(muebleSeleccionado.value)) return false
    return true
  })
})

onMounted(async () => {
  await Promise.all([
    ubicacionesStore.fetchUbicaciones(),
    habitacionesStore.fetchHabitaciones(),
    mueblesStore.fetchMuebles(),
  ])
})

async function cargarHabitaciones() {
  await habitacionesStore.fetchHabitaciones()
}

async function cargarMuebles() {
  const habitacionId = form.value.habitacion_id || habitacionSeleccionada.value
  if (!habitacionId) {
    await mueblesStore.fetchMuebles()
    return
  }
  await mueblesStore.fetchMuebles({ habitacion_id: habitacionId })
}

function abrirFormulario() {
  form.value = {
    habitacion_id: '',
    mueble_id: '',
    nombre: '',
  }
  // se recargarán los muebles al seleccionar habitación
  mostrarFormulario.value = true
}

async function guardar() {
  try {
    if (!form.value.mueble_id) {
      alert('Debes seleccionar un mueble')
      return
    }
    await ubicacionesStore.crearUbicacion({
      mueble_id: form.value.mueble_id,
      nombre: form.value.nombre,
    })
    mostrarFormulario.value = false
  } catch (e) {
    alert(e.response?.data?.message || 'Error al guardar la ubicación')
  }
}
</script>

<template>
  <div class="ubicaciones-view">
    <PageHeader title="Ubicaciones">
      <template #actions>
        <button class="btn btn-primary" @click="abrirFormulario">+ Nueva Ubicación</button>
      </template>
    </PageHeader>

    <FilterBar>
      <select
        v-model="habitacionSeleccionada"
        class="input"
        @change="cargarMuebles"
      >
        <option value="">Todas las habitaciones</option>
        <option
          v-for="hab in habitacionesStore.habitaciones"
          :key="hab.id"
          :value="hab.id"
        >
          {{ hab.nombre }}
        </option>
      </select>

      <select
        v-model="muebleSeleccionado"
        class="input"
      >
        <option value="">Todos los muebles</option>
        <option
          v-for="m in mueblesStore.muebles"
          :key="m.id"
          :value="m.id"
        >
          {{ m.nombre }}
        </option>
      </select>
    </FilterBar>

    <LoadingState v-if="ubicacionesStore.loading" text="Cargando ubicaciones..." />

    <EmptyState
      v-else-if="ubicacionesFiltradas.length === 0"
      text="No hay ubicaciones registradas."
    />

    <div v-else class="table-container">
      <table class="table">
        <thead>
          <tr>
            <th>Habitación</th>
            <th>Mueble</th>
            <th>Ubicación</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="u in ubicacionesFiltradas" :key="u.id">
            <td>{{ u.mueble?.habitacion?.nombre || '-' }}</td>
            <td>{{ u.mueble?.nombre || '-' }}</td>
            <td>{{ u.nombre }}</td>
          </tr>
        </tbody>
      </table>
    </div>

    <FormModal
      :visible="mostrarFormulario"
      title="Nueva Ubicación"
      @close="mostrarFormulario = false"
    >
      <form @submit.prevent="guardar">
        <div class="form-group">
          <label>Habitación</label>
          <select
            v-model="form.habitacion_id"
            class="input"
            required
            @change="cargarMuebles"
          >
            <option value="" disabled>Seleccionar habitación</option>
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
            v-model="form.mueble_id"
            class="input"
            required
          >
            <option value="" disabled>Seleccionar mueble</option>
            <option
              v-for="m in mueblesStore.muebles"
              :key="m.id"
              :value="m.id"
            >
              {{ m.nombre }}
            </option>
          </select>
        </div>

        <div class="form-group">
          <label>Nombre de la ubicación</label>
          <input
            v-model="form.nombre"
            type="text"
            class="input"
            placeholder="Ej: Estante superior"
            required
          />
        </div>

        <div class="form-actions">
          <button type="button" class="btn btn-secondary" @click="mostrarFormulario = false">
            Cancelar
          </button>
          <button type="submit" class="btn btn-primary">
            Guardar
          </button>
        </div>
      </form>
    </FormModal>
  </div>
</template>

<style scoped>
</style>

