<script setup>
import { ref, onMounted, computed } from 'vue'
import { useMueblesStore } from '../stores/muebles'
import { useHabitacionesStore } from '../stores/habitaciones'
import PageHeader from '../components/PageHeader.vue'
import FilterBar from '../components/FilterBar.vue'
import LoadingState from '../components/LoadingState.vue'
import EmptyState from '../components/EmptyState.vue'
import CardList from '../components/CardList.vue'
import FormModal from '../components/FormModal.vue'

const mueblesStore = useMueblesStore()
const habitacionesStore = useHabitacionesStore()

const mostrarFormulario = ref(false)
const editando = ref(null)
const habitacionFiltro = ref('')

const form = ref({
  habitacion_id: '',
  nombre: '',
})

const mueblesFiltrados = computed(() => {
  if (!habitacionFiltro.value) return mueblesStore.muebles
  return mueblesStore.muebles.filter(
    (m) => m.habitacion_id === Number(habitacionFiltro.value) || m.habitacion?.id === Number(habitacionFiltro.value),
  )
})

onMounted(async () => {
  await Promise.all([
    habitacionesStore.fetchHabitaciones(),
    mueblesStore.fetchMuebles(),
  ])
})

function abrirFormulario(mueble = null) {
  if (mueble) {
    editando.value = mueble.id
    form.value = {
      habitacion_id: mueble.habitacion_id || mueble.habitacion?.id || '',
      nombre: mueble.nombre,
    }
  } else {
    editando.value = null
    form.value = {
      habitacion_id: '',
      nombre: '',
    }
  }
  mostrarFormulario.value = true
}

async function guardar() {
  try {
    if (editando.value) {
      await mueblesStore.actualizarMueble(editando.value, form.value)
    } else {
      await mueblesStore.crearMueble(form.value)
    }
    mostrarFormulario.value = false
  } catch (e) {
    alert(e.response?.data?.message || 'Error al guardar el mueble')
  }
}

async function eliminar(id) {
  if (!confirm('¿Estás seguro de eliminar este mueble?')) return
  try {
    await mueblesStore.eliminarMueble(id)
  } catch (e) {
    alert(e.response?.data?.message || 'No se puede eliminar: puede tener ubicaciones asociadas')
  }
}
</script>

<template>
  <div class="muebles-view">
    <PageHeader title="Muebles">
      <template #actions>
        <button class="btn btn-primary" @click="abrirFormulario()">+ Nuevo Mueble</button>
      </template>
    </PageHeader>

    <FilterBar>
      <select v-model="habitacionFiltro" class="input">
        <option value="">Todas las habitaciones</option>
        <option v-for="hab in habitacionesStore.habitaciones" :key="hab.id" :value="hab.id">
          {{ hab.nombre }}
        </option>
      </select>
    </FilterBar>

    <LoadingState v-if="mueblesStore.loading" text="Cargando muebles..." />

    <EmptyState
      v-else-if="mueblesFiltrados.length === 0"
      text="No se encontraron muebles."
    />

    <CardList
      v-else
      :items="mueblesFiltrados"
      v-slot="{ item: m }"
    >
      <div class="card">
        <div class="card-info">
          <h3>{{ m.nombre }}</h3>
          <p class="card-subtext">{{ m.habitacion?.nombre || 'Sin habitación' }}</p>
          <span class="card-count card-count-success">{{ m.ubicaciones_count || 0 }} ubicaciones</span>
        </div>
        <div class="card-actions">
          <button class="btn btn-sm btn-secondary" @click="abrirFormulario(m)">Editar</button>
          <button class="btn btn-sm btn-danger" @click="eliminar(m.id)">Eliminar</button>
        </div>
      </div>
    </CardList>

    <FormModal
      :visible="mostrarFormulario"
      :title="editando ? 'Editar Mueble' : 'Nuevo Mueble'"
      @close="mostrarFormulario = false"
    >
      <form @submit.prevent="guardar">
        <div class="form-group">
          <label>Habitación</label>
          <select v-model="form.habitacion_id" class="input" required>
            <option value="" disabled>Seleccionar habitación</option>
            <option v-for="hab in habitacionesStore.habitaciones" :key="hab.id" :value="hab.id">
              {{ hab.nombre }}
            </option>
          </select>
        </div>

        <div class="form-group">
          <label>Nombre del mueble</label>
          <input v-model="form.nombre" type="text" class="input" required />
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
.filters {
  margin-bottom: 1.5rem;
}
</style>

