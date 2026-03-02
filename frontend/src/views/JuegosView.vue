<script setup>
import { ref, onMounted, computed } from 'vue'
import { useRoute } from 'vue-router'
import { useJuegosStore } from '../stores/juegos'
import { useCategoriasStore } from '../stores/categorias'
import { useHabitacionesStore } from '../stores/habitaciones'
import { useMueblesStore } from '../stores/muebles'
import { useUbicacionesStore } from '../stores/ubicaciones'
import PageHeader from '../components/PageHeader.vue'
import FilterBar from '../components/FilterBar.vue'
import LoadingState from '../components/LoadingState.vue'
import EmptyState from '../components/EmptyState.vue'
import FormModal from '../components/FormModal.vue'
import StatusBadge from '../components/StatusBadge.vue'
import LocationPicker from '../components/LocationPicker.vue'

const route = useRoute()
const juegosStore = useJuegosStore()
const categoriasStore = useCategoriasStore()
const habitacionesStore = useHabitacionesStore()
const mueblesStore = useMueblesStore()
const ubicacionesStore = useUbicacionesStore()

const backendUrl = import.meta.env.VITE_BACKEND_URL || 'http://localhost:8000'
const buscar = ref('')
const categoriaFiltro = ref('')
const habitacionFiltro = ref(route.query.habitacion_id || '')
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
  fecha_compra: '',
  habitacion_id: '',
  mueble_id: '',
  ubicacion_id: '',
})

const mueblesFiltrados = computed(() => {
  if (!form.value.habitacion_id) return mueblesStore.muebles
  return mueblesStore.muebles.filter(
    (m) =>
      m.habitacion_id === Number(form.value.habitacion_id) ||
      m.habitacion?.id === Number(form.value.habitacion_id),
  )
})

const ubicacionesFiltradas = computed(() => {
  if (!form.value.mueble_id) return []
  return ubicacionesStore.ubicaciones.filter(
    (u) => u.mueble_id === Number(form.value.mueble_id),
  )
})

const visiblePages = computed(() => {
  const last = juegosStore.pagination.lastPage || 1
  const current = juegosStore.pagination.currentPage || 1
  const items = []

  // Si hay pocas páginas, mostramos todas
  if (last <= 18) {
    for (let i = 1; i <= last; i++) items.push(i)
    return items
  }

  // Hasta la página 15: 15 primeras, ..., 3 últimas
  if (current <= 15) {
    for (let i = 1; i <= 15; i++) items.push(i)
    items.push('ellipsis-middle')
    for (let i = last - 2; i <= last; i++) items.push(i)
    return items
  }

  // A partir de la 15: 3 primeras, ..., 9 alrededor, ..., 3 últimas
  items.push(1, 2, 3)
  items.push('ellipsis-left')

  let start = current - 4
  let end = current + 4

  if (start < 4) start = 4
  if (end > last - 3) end = last - 3

  for (let i = start; i <= end; i++) {
    items.push(i)
  }

  items.push('ellipsis-right')
  items.push(last - 2, last - 1, last)

  return items
})

onMounted(async () => {
  juegosStore.fetchJuegos(buildParams())
  categoriasStore.fetchCategorias()
  await Promise.all([
    habitacionesStore.fetchHabitaciones(),
    mueblesStore.fetchMuebles(),
    ubicacionesStore.fetchUbicaciones(),
  ])
})

function buildParams(page = 1) {
  const params = { page }
  if (buscar.value) params.buscar = buscar.value
  if (categoriaFiltro.value) params.categoria_id = categoriaFiltro.value
   if (habitacionFiltro.value) params.habitacion_id = habitacionFiltro.value
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
    form.value = {
      nombre: juego.nombre,
      descripcion: juego.descripcion,
      edad_minima: juego.edad_minima,
      edad_maxima: juego.edad_maxima,
      num_jugadores_min: juego.num_jugadores_min,
      num_jugadores_max: juego.num_jugadores_max,
      categoria_id: juego.categoria_id,
      estado: juego.estado,
      fecha_compra: juego.fecha_compra || '',
      habitacion_id: juego.ubicacion?.mueble?.habitacion?.id || '',
      mueble_id: juego.ubicacion?.mueble?.id || '',
      ubicacion_id: juego.ubicacion?.id || '',
    }
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
      fecha_compra: '',
      habitacion_id: '',
      mueble_id: '',
      ubicacion_id: '',
    }
  }
  mostrarFormulario.value = true
}

function onHabitacionChange() {
  form.value.mueble_id = ''
  form.value.ubicacion_id = ''
}

function onMuebleChange() {
  form.value.ubicacion_id = ''
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
    <PageHeader title="Juegos">
      <template #actions>
        <button class="btn btn-primary" @click="abrirFormulario()">+ Nuevo Juego</button>
      </template>
    </PageHeader>

    <FilterBar>
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
    </FilterBar>

    <LoadingState v-if="juegosStore.loading" text="Cargando juegos..." />

    <EmptyState
      v-else-if="juegosStore.juegos.length === 0"
      text="No se encontraron juegos."
    />

    <div v-else>
      <div class="table-container">
        <table class="table">
          <thead>
            <tr>
              <th class="th-imagen">Imagen</th>
              <th>Nombre</th>
              <th>Categoría</th>
              <th>Jugadores</th>
              <th>Edad</th>
              <th>Fecha compra</th>
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
              <td>{{ juego.fecha_compra || '-' }}</td>
              <td>
                <StatusBadge :value="juego.estado" type="juego" />
              </td>
              <td class="actions">
                <div class="actions-inner">
                  <button class="btn btn-sm btn-secondary" @click="abrirFormulario(juego)">Editar</button>
                  <button class="btn btn-sm btn-danger" @click="eliminar(juego.id)">Eliminar</button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div v-if="juegosStore.pagination.lastPage > 1" class="pagination">
        <button
          class="btn btn-sm btn-secondary"
          :disabled="juegosStore.pagination.currentPage <= 1"
          @click="irAPagina(juegosStore.pagination.currentPage - 1)"
        >
          ← Anterior
        </button>

        <div class="pagination-pages">
          <template v-for="item in visiblePages" :key="`page-${item}`">
            <button
              v-if="typeof item === 'number'"
              class="btn btn-sm"
              :class="item === juegosStore.pagination.currentPage ? 'btn-primary' : 'btn-secondary'"
              @click="irAPagina(item)"
            >
              {{ item }}
            </button>
            <span v-else class="pagination-ellipsis">...</span>
          </template>
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

    <FormModal
      :visible="mostrarFormulario"
      :title="editando ? 'Editar Juego' : 'Nuevo Juego'"
      @close="mostrarFormulario = false"
    >
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
          <LocationPicker v-model="form.ubicacion_id" />
          <div class="form-group">
            <label>Fecha de compra</label>
            <input v-model="form.fecha_compra" type="date" class="input" />
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
    </FormModal>
  </div>
</template>

<style scoped>
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

.juegos-view .table th,
.juegos-view .table td {
  vertical-align: middle;
}

.juegos-view .table tbody tr {
  height: 72px;
}

.actions-inner {
  display: inline-flex;
  gap: 0.5rem;
  white-space: nowrap;
  align-items: center;
}

/* Centrar y limitar el ancho de la tabla en escritorio */
@media (min-width: 901px) {
  .juegos-view .table {
    width: 100%;
    max-width: none;
  }
}

/* Ajustes de ancho de columnas en escritorio */
@media (min-width: 901px) {
  .juegos-view .table th:nth-child(2),
  .juegos-view .table td:nth-child(2) {
    /* Nombre */
    max-width: 200px;
  }

  .juegos-view .table th:nth-child(3),
  .juegos-view .table td:nth-child(3) {
    /* Categoría */
    width: 18%;
  }

  .juegos-view .table th:nth-child(4),
  .juegos-view .table td:nth-child(4) {
    /* Jugadores */
    width: 90px;
    white-space: nowrap;
  }

  .juegos-view .table th:nth-child(5),
  .juegos-view .table td:nth-child(5) {
    /* Edad */
    width: 70px;
    white-space: nowrap;
  }

  .juegos-view .table th:nth-child(6),
  .juegos-view .table td:nth-child(6) {
    /* Fecha compra */
    width: 110px;
    white-space: nowrap;
  }

  .juegos-view .table th:nth-child(7),
  .juegos-view .table td:nth-child(7) {
    /* Estado */
    width: 110px;
    white-space: nowrap;
  }

  .juegos-view .table th:nth-child(8),
  .juegos-view .table td:nth-child(8) {
    /* Acciones */
    width: 210px;
    white-space: nowrap;
  }
}

@media (max-width: 900px) {
  .juegos-view .table {
    min-width: 800px;
  }

  .th-imagen,
  .td-imagen {
    display: none;
  }
}

@media (max-width: 700px) {
  /* Ocultar columnas de Jugadores y Edad para que la tabla quepa mejor */
  .juegos-view .table th:nth-child(4),
  .juegos-view .table td:nth-child(4),
  .juegos-view .table th:nth-child(5),
  .juegos-view .table td:nth-child(5) {
    display: none;
  }
}
</style>
