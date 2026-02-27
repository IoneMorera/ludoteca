<script setup>
import { ref, onMounted } from 'vue'
import { useJuegosStore } from '../stores/juegos'
import { useCategoriasStore } from '../stores/categorias'

const juegosStore = useJuegosStore()
const categoriasStore = useCategoriasStore()

const backendUrl = import.meta.env.VITE_BACKEND_URL || 'http://localhost:8000'
const buscar = ref('')
const categoriaFiltro = ref('')
const mostrarFormulario = ref(false)
const editando = ref(null)

const form = ref({
  nombre: '',
  descripcion: '',
  edad_minima: null,
  edad_maxima: null,
  num_jugadores_min: null,
  num_jugadores_max: null,
  categoria_id: '',
  estado: 'disponible',
})

onMounted(() => {
  juegosStore.fetchJuegos()
  categoriasStore.fetchCategorias()
})

function buildParams(page = 1) {
  const params = { page }
  if (buscar.value) params.buscar = buscar.value
  if (categoriaFiltro.value) params.categoria_id = categoriaFiltro.value
  return params
}

function filtrar() {
  juegosStore.fetchJuegos(buildParams(1))
}

function irAPagina(page) {
  juegosStore.fetchJuegos(buildParams(page))
}

function abrirFormulario(juego = null) {
  if (juego) {
    editando.value = juego.id
    form.value = { ...juego }
  } else {
    editando.value = null
    form.value = {
      nombre: '',
      descripcion: '',
      edad_minima: null,
      edad_maxima: null,
      num_jugadores_min: null,
      num_jugadores_max: null,
      categoria_id: '',
      estado: 'disponible',
    }
  }
  mostrarFormulario.value = true
}

async function guardar() {
  try {
    if (editando.value) {
      await juegosStore.actualizarJuego(editando.value, form.value)
    } else {
      await juegosStore.crearJuego(form.value)
    }
    mostrarFormulario.value = false
    juegosStore.fetchJuegos()
  } catch (e) {
    alert(e.response?.data?.message || 'Error al guardar')
  }
}

async function eliminar(id) {
  if (!confirm('¿Estás seguro de eliminar este juego?')) return
  try {
    await juegosStore.eliminarJuego(id)
  } catch (e) {
    alert(e.response?.data?.message || 'Error al eliminar')
  }
}

function estadoClase(estado) {
  const clases = {
    disponible: 'badge-success',
    prestado: 'badge-warning',
    reparacion: 'badge-info',
    baja: 'badge-danger',
  }
  return clases[estado] || ''
}
</script>

<template>
  <div class="juegos-view">
    <div class="page-header">
      <h1 class="page-title">Juegos</h1>
      <button class="btn btn-primary" @click="abrirFormulario()">+ Nuevo Juego</button>
    </div>

    <div class="filters">
      <input
        v-model="buscar"
        type="text"
        placeholder="Buscar juegos..."
        class="input"
        @input="filtrar"
      />
      <select v-model="categoriaFiltro" class="input" @change="filtrar">
        <option value="">Todas las categorías</option>
        <option v-for="cat in categoriasStore.categorias" :key="cat.id" :value="cat.id">
          {{ cat.nombre }}
        </option>
      </select>
    </div>

    <div v-if="juegosStore.loading" class="loading">Cargando juegos...</div>

    <div v-else-if="juegosStore.juegos.length === 0" class="empty">
      No se encontraron juegos.
    </div>

    <div v-else class="table-container">
      <table class="table">
        <thead>
          <tr>
            <th class="th-imagen">Imagen</th>
            <th>Nombre</th>
            <th>Categoría</th>
            <th>Jugadores</th>
            <th>Edad</th>
            <th>Estado</th>
            <th>Acciones</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="juego in juegosStore.juegos" :key="juego.id">
            <td class="td-imagen">
              <img
                v-if="juego.imagen"
                :src="backendUrl + juego.imagen"
                :alt="juego.nombre"
                class="juego-thumb"
              />
              <span v-else class="no-thumb">🎲</span>
            </td>
            <td>
              <router-link :to="`/juegos/${juego.id}`" class="link">
                {{ juego.nombre }}
              </router-link>
            </td>
            <td>{{ juego.categoria?.nombre || '-' }}</td>
            <td>{{ juego.num_jugadores_min }}–{{ juego.num_jugadores_max }}</td>
            <td>{{ juego.edad_minima }}+</td>
            <td><span class="badge" :class="estadoClase(juego.estado)">{{ juego.estado }}</span></td>
            <td class="actions">
              <button class="btn btn-sm btn-secondary" @click="abrirFormulario(juego)">Editar</button>
              <button class="btn btn-sm btn-danger" @click="eliminar(juego.id)">Eliminar</button>
            </td>
          </tr>
        </tbody>
      </table>

      <div v-if="juegosStore.pagination.lastPage > 1" class="pagination">
        <button
          class="btn btn-sm btn-secondary"
          :disabled="juegosStore.pagination.currentPage <= 1"
          @click="irAPagina(juegosStore.pagination.currentPage - 1)"
        >
          ← Anterior
        </button>

        <div class="pagination-pages">
          <button
            v-for="page in juegosStore.pagination.lastPage"
            :key="page"
            class="btn btn-sm"
            :class="page === juegosStore.pagination.currentPage ? 'btn-primary' : 'btn-secondary'"
            @click="irAPagina(page)"
          >
            {{ page }}
          </button>
        </div>

        <button
          class="btn btn-sm btn-secondary"
          :disabled="juegosStore.pagination.currentPage >= juegosStore.pagination.lastPage"
          @click="irAPagina(juegosStore.pagination.currentPage + 1)"
        >
          Siguiente →
        </button>

        <span class="pagination-info">
          {{ juegosStore.pagination.total }} juegos en total
        </span>
      </div>
    </div>

    <div v-if="mostrarFormulario" class="modal-overlay" @click.self="mostrarFormulario = false">
      <div class="modal">
        <h2>{{ editando ? 'Editar Juego' : 'Nuevo Juego' }}</h2>
        <form @submit.prevent="guardar">
          <div class="form-group">
            <label>Nombre</label>
            <input v-model="form.nombre" type="text" class="input" required />
          </div>
          <div class="form-group">
            <label>Descripción</label>
            <textarea v-model="form.descripcion" class="input" rows="3"></textarea>
          </div>
          <div class="form-row">
            <div class="form-group">
              <label>Categoría</label>
              <select v-model="form.categoria_id" class="input" required>
                <option value="" disabled>Seleccionar</option>
                <option v-for="cat in categoriasStore.categorias" :key="cat.id" :value="cat.id">
                  {{ cat.nombre }}
                </option>
              </select>
            </div>
            <div class="form-group">
              <label>Estado</label>
              <select v-model="form.estado" class="input">
                <option value="disponible">Disponible</option>
                <option value="prestado">Prestado</option>
                <option value="reparacion">En reparación</option>
                <option value="baja">Baja</option>
              </select>
            </div>
          </div>
          <div class="form-row">
            <div class="form-group">
              <label>Jugadores mín.</label>
              <input v-model.number="form.num_jugadores_min" type="number" class="input" min="1" />
            </div>
            <div class="form-group">
              <label>Jugadores máx.</label>
              <input v-model.number="form.num_jugadores_max" type="number" class="input" min="1" />
            </div>
            <div class="form-group">
              <label>Edad mínima</label>
              <input v-model.number="form.edad_minima" type="number" class="input" min="0" />
            </div>
          </div>
          <div class="form-actions">
            <button type="button" class="btn btn-secondary" @click="mostrarFormulario = false">Cancelar</button>
            <button type="submit" class="btn btn-primary">Guardar</button>
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
  display: flex;
  gap: 1rem;
  margin-bottom: 1.5rem;
}

.filters .input {
  flex: 1;
}

.th-imagen,
.td-imagen {
  width: 60px;
  text-align: center;
}

.juego-thumb {
  width: 48px;
  height: 48px;
  object-fit: cover;
  border-radius: 6px;
}

.no-thumb {
  font-size: 1.5rem;
  opacity: 0.3;
}

.link {
  color: #2d5a87;
  text-decoration: none;
  font-weight: 600;
}

.link:hover {
  text-decoration: underline;
}

.actions {
  display: flex;
  gap: 0.5rem;
}

.pagination {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  margin-top: 1.25rem;
  flex-wrap: wrap;
}

.pagination-pages {
  display: flex;
  gap: 0.25rem;
}

.pagination-info {
  margin-left: auto;
  font-size: 0.85rem;
  color: #888;
}

.form-row {
  display: flex;
  gap: 1rem;
}

.form-row .form-group {
  flex: 1;
}
</style>
