<script setup>
import { ref, onMounted, computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useJuegosStore } from '../stores/juegos'
import { useCategoriasStore } from '../stores/categorias'
import { usePropietariosStore } from '../stores/propietarios'
import StatusBadge from '../components/StatusBadge.vue'
import FormModal from '../components/FormModal.vue'
import LocationPicker from '../components/LocationPicker.vue'

const route = useRoute()
const router = useRouter()
const juegosStore = useJuegosStore()
const categoriasStore = useCategoriasStore()
const propietariosStore = usePropietariosStore()
const backendUrl = import.meta.env.VITE_BACKEND_URL || 'http://localhost:8000'

const mostrarFormulario = ref(false)
const form = ref({})

onMounted(async () => {
  await juegosStore.fetchJuego(route.params.id)
  categoriasStore.fetchCategorias()
  propietariosStore.fetchPropietarios()
})

const juego = computed(() => juegosStore.juego)

const propietariosTexto = computed(() => {
  if (!juego.value?.propietarios?.length) return 'Sin propietarios'
  return juego.value.propietarios.map((p) => p.nombre).join(', ')
})

const esExpansion = computed(() => !!juego.value?.juego_base_id)
const tieneExpansiones = computed(() => juego.value?.expansiones?.length > 0)

function abrirEdicion() {
  const j = juego.value
  form.value = {
    nombre: j.nombre,
    descripcion: j.descripcion || '',
    edad_minima: j.edad_minima,
    edad_maxima: j.edad_maxima,
    num_jugadores_min: j.num_jugadores_min,
    num_jugadores_max: j.num_jugadores_max,
    categoria_id: j.categoria_id,
    estado: j.estado,
    fecha_compra: j.fecha_compra || '',
    ubicacion_id: j.ubicacion?.id || '',
    propietario_ids: j.propietarios?.map((p) => p.id) || [],
    juego_base_id: j.juego_base_id || '',
  }
  mostrarFormulario.value = true
}

async function guardar() {
  try {
    await juegosStore.actualizarJuego(juego.value.id, form.value)
    mostrarFormulario.value = false
    await juegosStore.fetchJuego(route.params.id)
  } catch (e) {
    alert(e.response?.data?.message || 'Error al guardar')
  }
}
</script>

<template>
  <div class="detalle-view">
    <div class="detalle-actions">
      <button class="btn btn-secondary" @click="router.back()">← Volver</button>
      <button v-if="juego" class="btn btn-primary" @click="abrirEdicion">Editar</button>
    </div>

    <div v-if="juegosStore.loading" class="loading">Cargando...</div>

    <div v-else-if="juego" class="detalle-card">
      <div class="detalle-header">
        <img
          v-if="juego.imagen"
          :src="backendUrl + juego.imagen"
          :alt="juego.nombre"
          class="detalle-cover"
        />
        <div>
          <h1>
            {{ juego.nombre }}
            <span v-if="esExpansion" class="expansion-badge">Expansión</span>
          </h1>
          <p class="descripcion">{{ juego.descripcion || 'Sin descripción' }}</p>
          <div v-if="esExpansion && juego.juego_base" class="juego-base-link">
            Juego base:
            <router-link :to="`/juegos/${juego.juego_base.id}`" class="link">
              {{ juego.juego_base.nombre }}
            </router-link>
          </div>
        </div>
      </div>

      <div class="info-grid">
        <div class="info-item">
          <span class="info-label">Categoría</span>
          <span class="info-value">{{ juego.categoria?.nombre || '-' }}</span>
        </div>
        <div class="info-item">
          <span class="info-label">Jugadores</span>
          <span class="info-value">{{ juego.num_jugadores_min }} – {{ juego.num_jugadores_max }}</span>
        </div>
        <div class="info-item">
          <span class="info-label">Edad mínima</span>
          <span class="info-value">{{ juego.edad_minima }}+</span>
        </div>
        <div class="info-item">
          <span class="info-label">Estado</span>
          <span class="info-value">
            <StatusBadge :value="juego.estado" type="juego" />
          </span>
        </div>
        <div class="info-item">
          <span class="info-label">Fecha de compra</span>
          <span class="info-value">{{ juego.fecha_compra || '-' }}</span>
        </div>
        <div class="info-item">
          <span class="info-label">Ubicación</span>
          <span class="info-value">
            <template v-if="juego.ubicacion">
              {{ juego.ubicacion.mueble?.habitacion?.nombre || 'Sin habitación' }}
              ›
              {{ juego.ubicacion.mueble?.nombre || 'Sin mueble' }}
              ›
              {{ juego.ubicacion.nombre }}
            </template>
            <template v-else>
              Sin ubicación asignada
            </template>
          </span>
        </div>
        <div class="info-item">
          <span class="info-label">Propietarios</span>
          <span class="info-value">{{ propietariosTexto }}</span>
        </div>
      </div>

      <div v-if="tieneExpansiones" class="expansiones-section">
        <h2>Expansiones</h2>
        <div class="expansiones-grid">
          <div v-for="exp in juego.expansiones" :key="exp.id" class="expansion-card">
            <router-link :to="`/juegos/${exp.id}`" class="link">
              {{ exp.nombre }}
            </router-link>
            <div class="expansion-meta">
              <span v-if="exp.propietarios?.length" class="expansion-owners">
                {{ exp.propietarios.map(p => p.nombre).join(', ') }}
              </span>
              <template v-if="exp.ubicacion">
                <span class="expansion-location">
                  {{ exp.ubicacion.mueble?.habitacion?.nombre }} ›
                  {{ exp.ubicacion.mueble?.nombre }} ›
                  {{ exp.ubicacion.nombre }}
                </span>
              </template>
            </div>
          </div>
        </div>
      </div>

      <div v-if="juego.prestamos?.length" class="prestamos-section">
        <h2>Historial de Préstamos</h2>
        <table class="table">
          <thead>
            <tr>
              <th>Persona</th>
              <th>Fecha Préstamo</th>
              <th>Devolución Prevista</th>
              <th>Devolución Real</th>
              <th>Estado</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="p in juego.prestamos" :key="p.id">
              <td>{{ p.persona }}</td>
              <td>{{ p.fecha_prestamo }}</td>
              <td>{{ p.fecha_devolucion_prevista }}</td>
              <td>{{ p.fecha_devolucion_real || '-' }}</td>
              <td>{{ p.estado }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <FormModal
      :visible="mostrarFormulario"
      title="Editar Juego"
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
        <div class="form-group">
          <label>Propietarios</label>
          <div class="propietarios-checkboxes">
            <label
              v-for="prop in propietariosStore.propietarios"
              :key="prop.id"
              class="checkbox-label"
            >
              <input
                type="checkbox"
                :value="prop.id"
                v-model="form.propietario_ids"
              />
              {{ prop.nombre }}
            </label>
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
.detalle-view {
  max-width: 1024px;
}

.detalle-actions {
  display: flex;
  gap: 0.75rem;
  align-items: center;
}

.propietarios-checkboxes {
  display: flex;
  flex-wrap: wrap;
  gap: 0.75rem;
  padding: 0.5rem 0;
}

.checkbox-label {
  display: inline-flex;
  align-items: center;
  gap: 0.3rem;
  font-size: 0.9rem;
  cursor: pointer;
  font-weight: normal;
  color: var(--text-main);
}

.detalle-card {
  background: var(--bg-surface);
  border-radius: 12px;
  padding: 2rem;
  margin-top: 1rem;
  box-shadow: var(--shadow-soft);
  border: 1px solid var(--border-soft);
}

.detalle-header {
  display: flex;
  gap: 1.5rem;
  align-items: flex-start;
  margin-bottom: 1.5rem;
}

.detalle-cover {
  width: 140px;
  height: 140px;
  object-fit: contain;
  border-radius: 10px;
  background: var(--bg-surface-soft);
  flex-shrink: 0;
}

.detalle-header h1 {
  color: var(--primary);
  margin-bottom: 0.5rem;
}

.descripcion {
  color: var(--text-muted);
}

.expansion-badge {
  display: inline-block;
  font-size: 0.75rem;
  background: #e3f2fd;
  color: #1565c0;
  padding: 0.15rem 0.6rem;
  border-radius: 8px;
  vertical-align: middle;
  margin-left: 0.5rem;
  font-weight: 600;
}

.juego-base-link {
  margin-top: 0.5rem;
  font-size: 0.9rem;
  color: var(--text-muted);
}

.juego-base-link .link {
  color: var(--primary);
  text-decoration: none;
  font-weight: 600;
}

.juego-base-link .link:hover {
  text-decoration: underline;
}

.info-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
  gap: 1rem;
  margin-bottom: 2rem;
}

.info-item {
  background: var(--bg-surface-soft);
  padding: 1rem;
  border-radius: 8px;
}

.info-label {
  display: block;
  font-size: 0.8rem;
  color: var(--text-muted);
  margin-bottom: 0.25rem;
}

.info-value {
  font-size: 1.1rem;
  font-weight: 600;
  color: var(--text-main);
}

.expansiones-section {
  margin-top: 1.5rem;
  margin-bottom: 1.5rem;
}

.expansiones-section h2 {
  font-size: 1.2rem;
  color: var(--primary);
  margin-bottom: 0.75rem;
}

.expansiones-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 0.75rem;
}

.expansion-card {
  background: var(--bg-surface-soft);
  border-radius: 8px;
  padding: 0.85rem 1rem;
  border: 1px solid var(--border-soft);
}

.expansion-card .link {
  color: var(--primary);
  text-decoration: none;
  font-weight: 600;
  font-size: 0.95rem;
}

.expansion-card .link:hover {
  text-decoration: underline;
}

.expansion-meta {
  display: flex;
  flex-direction: column;
  gap: 0.2rem;
  margin-top: 0.35rem;
  font-size: 0.8rem;
  color: var(--text-muted);
}

.prestamos-section {
  margin-top: 1.5rem;
}

.prestamos-section h2 {
  font-size: 1.2rem;
  color: var(--primary);
  margin-bottom: 0.75rem;
}
</style>
