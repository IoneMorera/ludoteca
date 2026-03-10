<script setup>
import { ref, onMounted } from 'vue'
import { formatDate } from '../utils/format'
import { usePrestamosStore } from '../stores/prestamos'
import { useJuegosStore } from '../stores/juegos'
import PageHeader from '../components/PageHeader.vue'
import FilterBar from '../components/FilterBar.vue'
import LoadingState from '../components/LoadingState.vue'
import EmptyState from '../components/EmptyState.vue'
import FormModal from '../components/FormModal.vue'
import StatusBadge from '../components/StatusBadge.vue'

const prestamosStore = usePrestamosStore()
const juegosStore = useJuegosStore()

const filtroEstado = ref('')
const mostrarFormulario = ref(false)

const form = ref({
  juego_id: '',
  persona: '',
  fecha_prestamo: new Date().toISOString().split('T')[0],
  fecha_devolucion_prevista: '',
  observaciones: '',
})

onMounted(() => {
  prestamosStore.fetchPrestamos()
  juegosStore.fetchJuegos({ estado: 'disponible' })
})

function filtrar() {
  const params = {}
  if (filtroEstado.value) params.estado = filtroEstado.value
  prestamosStore.fetchPrestamos(params)
}

function abrirFormulario() {
  form.value = {
    juego_id: '',
    persona: '',
    fecha_prestamo: new Date().toISOString().split('T')[0],
    fecha_devolucion_prevista: '',
    observaciones: '',
  }
  mostrarFormulario.value = true
}

async function crearPrestamo() {
  try {
    await prestamosStore.crearPrestamo(form.value)
    mostrarFormulario.value = false
    prestamosStore.fetchPrestamos()
    juegosStore.fetchJuegos({ estado: 'disponible' })
  } catch (e) {
    alert(e.response?.data?.message || 'Error al crear el préstamo')
  }
}

async function devolver(id) {
  if (!confirm('¿Confirmar la devolución de este juego?')) return
  try {
    await prestamosStore.devolverPrestamo(id)
    juegosStore.fetchJuegos({ estado: 'disponible' })
  } catch (e) {
    alert(e.response?.data?.message || 'Error al procesar la devolución')
  }
}

function estadoClase(estado) {
  const clases = {
    activo: 'badge-warning',
    devuelto: 'badge-success',
    retrasado: 'badge-danger',
  }
  return clases[estado] || ''
}
</script>

<template>
  <div class="prestamos-view">
    <PageHeader title="Préstamos">
      <template #actions>
        <button class="btn btn-primary" @click="abrirFormulario">+ Nuevo Préstamo</button>
      </template>
    </PageHeader>

    <FilterBar>
      <select v-model="filtroEstado" class="input" @change="filtrar">
        <option value="">Todos los estados</option>
        <option value="activo">Activos</option>
        <option value="devuelto">Devueltos</option>
        <option value="retrasado">Retrasados</option>
      </select>
    </FilterBar>

    <LoadingState v-if="prestamosStore.loading" text="Cargando préstamos..." />

    <EmptyState
      v-else-if="prestamosStore.prestamos.length === 0"
      text="No se encontraron préstamos."
    />

    <div v-else>
      <div class="table-container">
        <table class="table">
          <thead>
            <tr>
              <th>Juego</th>
              <th>Persona</th>
              <th>Fecha Préstamo</th>
              <th>Dev. Prevista</th>
              <th>Dev. Real</th>
              <th>Estado</th>
              <th>Acciones</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="p in prestamosStore.prestamos" :key="p.id">
              <td>{{ p.juego?.nombre }}</td>
              <td>{{ p.persona }}</td>
              <td>{{ formatDate(p.fecha_prestamo) }}</td>
              <td>{{ formatDate(p.fecha_devolucion_prevista) }}</td>
              <td>{{ formatDate(p.fecha_devolucion_real) }}</td>
              <td>
                <StatusBadge :value="p.estado" type="prestamo" />
              </td>
              <td>
                <button
                  v-if="p.estado === 'activo'"
                  class="btn btn-sm btn-primary"
                  @click="devolver(p.id)"
                >
                  Devolver
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="cards-mobile">
        <div v-for="p in prestamosStore.prestamos" :key="'card-' + p.id" class="prestamo-card">
          <div class="prestamo-card__header">
            <span class="prestamo-card__juego">{{ p.juego?.nombre }}</span>
            <StatusBadge :value="p.estado" type="prestamo" />
          </div>
          <div class="prestamo-card__body">
            <div class="prestamo-card__row">
              <span class="prestamo-card__label">Persona</span>
              <span>{{ p.persona }}</span>
            </div>
            <div class="prestamo-card__row">
              <span class="prestamo-card__label">Préstamo</span>
              <span>{{ formatDate(p.fecha_prestamo) }}</span>
            </div>
            <div class="prestamo-card__row">
              <span class="prestamo-card__label">Dev. prevista</span>
              <span>{{ formatDate(p.fecha_devolucion_prevista) }}</span>
            </div>
            <div v-if="p.fecha_devolucion_real" class="prestamo-card__row">
              <span class="prestamo-card__label">Dev. real</span>
              <span>{{ formatDate(p.fecha_devolucion_real) }}</span>
            </div>
          </div>
          <div v-if="p.estado === 'activo'" class="prestamo-card__actions">
            <button class="btn btn-sm btn-primary" @click="devolver(p.id)">Devolver</button>
          </div>
        </div>
      </div>
    </div>

    <FormModal
      :visible="mostrarFormulario"
      title="Nuevo Préstamo"
      @close="mostrarFormulario = false"
    >
      <form @submit.prevent="crearPrestamo">
          <div class="form-group">
            <label>Juego</label>
            <select v-model="form.juego_id" class="input" required>
              <option value="" disabled>Seleccionar juego</option>
              <option v-for="j in juegosStore.juegos" :key="j.id" :value="j.id">
                {{ j.nombre }}
              </option>
            </select>
          </div>
          <div class="form-group">
            <label>Persona</label>
            <input
              v-model="form.persona"
              type="text"
              class="input"
              placeholder="Nombre de la persona"
              required
            />
          </div>
          <div class="form-row">
            <div class="form-group">
              <label>Fecha de préstamo</label>
              <input v-model="form.fecha_prestamo" type="date" class="input" required />
            </div>
            <div class="form-group">
              <label>Fecha devolución prevista</label>
              <input v-model="form.fecha_devolucion_prevista" type="date" class="input" required />
            </div>
          </div>
          <div class="form-group">
            <label>Observaciones</label>
            <textarea v-model="form.observaciones" class="input" rows="2"></textarea>
          </div>
          <div class="form-actions">
            <button type="button" class="btn btn-secondary" @click="mostrarFormulario = false">Cancelar</button>
            <button type="submit" class="btn btn-primary">Crear Préstamo</button>
          </div>
        </form>
    </FormModal>
  </div>
</template>

<style scoped>
.filters {
  max-width: 1024px;
}

.prestamo-card {
  background: var(--bg-surface);
  border-radius: 10px;
  box-shadow: var(--shadow-soft);
  border: 1px solid var(--border-soft);
  overflow: hidden;
}

.prestamo-card__header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0.75rem 1rem;
  background: var(--bg-surface-soft);
  border-bottom: 1px solid var(--border-soft);
}

.prestamo-card__juego {
  font-weight: 700;
  color: var(--primary);
  font-size: 0.95rem;
}

.prestamo-card__body {
  padding: 0.65rem 1rem;
  display: flex;
  flex-direction: column;
  gap: 0.3rem;
}

.prestamo-card__row {
  display: flex;
  justify-content: space-between;
  font-size: 0.88rem;
}

.prestamo-card__label {
  font-size: 0.78rem;
  font-weight: 600;
  color: var(--text-muted);
  text-transform: uppercase;
  letter-spacing: 0.3px;
}

.prestamo-card__actions {
  padding: 0.6rem 1rem;
  border-top: 1px solid var(--border-soft);
  background: var(--bg-surface-soft);
}
</style>
