<script setup>
import { ref, onMounted } from 'vue'
import { usePrestamosStore } from '../stores/prestamos'
import { useJuegosStore } from '../stores/juegos'

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
    <div class="page-header">
      <h1 class="page-title">Préstamos</h1>
      <button class="btn btn-primary" @click="abrirFormulario">+ Nuevo Préstamo</button>
    </div>

    <div class="filters">
      <select v-model="filtroEstado" class="input" @change="filtrar">
        <option value="">Todos los estados</option>
        <option value="activo">Activos</option>
        <option value="devuelto">Devueltos</option>
        <option value="retrasado">Retrasados</option>
      </select>
    </div>

    <div v-if="prestamosStore.loading" class="loading">Cargando préstamos...</div>

    <div v-else-if="prestamosStore.prestamos.length === 0" class="empty">
      No se encontraron préstamos.
    </div>

    <div v-else class="table-container">
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
            <td>{{ p.fecha_prestamo }}</td>
            <td>{{ p.fecha_devolucion_prevista }}</td>
            <td>{{ p.fecha_devolucion_real || '-' }}</td>
            <td><span class="badge" :class="estadoClase(p.estado)">{{ p.estado }}</span></td>
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

    <div v-if="mostrarFormulario" class="modal-overlay" @click.self="mostrarFormulario = false">
      <div class="modal">
        <h2>Nuevo Préstamo</h2>
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
      </div>
    </div>
  </div>
</template>

<style scoped>
.page-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 1.5rem;
}

.page-title {
  font-size: 1.8rem;
  color: #1e3a5f;
}

.filters {
  margin-bottom: 1.5rem;
  max-width: 300px;
}

.form-row {
  display: flex;
  gap: 1rem;
}

.form-row .form-group {
  flex: 1;
}
</style>
