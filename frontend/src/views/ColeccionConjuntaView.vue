<script setup>
import { ref, onMounted, computed } from 'vue'
import { usePropietariosStore } from '../stores/propietarios'
import PageHeader from '../components/PageHeader.vue'
import LoadingState from '../components/LoadingState.vue'
import EmptyState from '../components/EmptyState.vue'
import StatusBadge from '../components/StatusBadge.vue'

const store = usePropietariosStore()
const backendUrl = import.meta.env.VITE_BACKEND_URL || 'http://localhost:8000'

const seleccionados = ref([])
const haConsultado = ref(false)

const juegos = computed(() => store.coleccionConjunta?.juegos || [])
const propietariosSeleccionados = computed(() => store.coleccionConjunta?.propietarios || [])

onMounted(() => {
  store.fetchPropietarios()
})

function togglePropietario(id) {
  const idx = seleccionados.value.indexOf(id)
  if (idx === -1) {
    seleccionados.value.push(id)
  } else {
    seleccionados.value.splice(idx, 1)
  }
}

async function buscar() {
  if (seleccionados.value.length === 0) return
  haConsultado.value = true
  await store.fetchColeccionConjunta(seleccionados.value)
}

function propietariosTexto(props) {
  if (!props || props.length === 0) return '-'
  return props.map((p) => p.nombre).join(', ')
}

function esCompartido(juego) {
  return juego.propietarios && juego.propietarios.length > 1
}

function tituloColeccion() {
  if (!propietariosSeleccionados.value.length) return 'Colección Conjunta'
  return `Colección de ${propietariosSeleccionados.value.map((p) => p.nombre).join(' + ')}`
}
</script>

<template>
  <div class="coleccion-conjunta-view">
    <PageHeader title="Colección Conjunta">
      <template #subtitle>
        Selecciona los propietarios para ver su colección combinada
      </template>
    </PageHeader>

    <div class="selector-propietarios">
      <div class="propietarios-chips">
        <button
          v-for="prop in store.propietarios"
          :key="prop.id"
          class="chip"
          :class="{ 'chip-active': seleccionados.includes(prop.id) }"
          @click="togglePropietario(prop.id)"
        >
          {{ prop.nombre }}
          <span v-if="seleccionados.includes(prop.id)" class="chip-check">✓</span>
        </button>
      </div>
      <button
        class="btn btn-primary"
        :disabled="seleccionados.length === 0"
        @click="buscar"
      >
        Ver colección conjunta
      </button>
    </div>

    <LoadingState v-if="store.loading" text="Cargando colección conjunta..." />

    <template v-else-if="haConsultado">
      <h2 class="coleccion-titulo">{{ tituloColeccion() }}</h2>
      <p class="coleccion-subtitulo">{{ juegos.length }} juegos en total</p>

      <EmptyState
        v-if="juegos.length === 0"
        text="No se encontraron juegos para esta combinación."
      />

      <div v-else class="table-container">
        <table class="table">
          <thead>
            <tr>
              <th class="th-imagen">Imagen</th>
              <th>Nombre</th>
              <th>Propietarios</th>
              <th>Categoría</th>
              <th>Estado</th>
              <th>Ubicación</th>
              <th>Expansiones</th>
            </tr>
          </thead>
          <tbody>
            <template v-for="juego in juegos" :key="juego.id">
              <tr :class="{ 'fila-compartida': esCompartido(juego) }">
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
                <td>
                  <span v-if="esCompartido(juego)" class="badge badge-info">
                    Compartido
                  </span>
                  {{ propietariosTexto(juego.propietarios) }}
                </td>
                <td>{{ juego.categoria?.nombre || '-' }}</td>
                <td>
                  <StatusBadge :value="juego.estado" type="juego" />
                </td>
                <td>
                  <template v-if="juego.ubicacion">
                    {{ juego.ubicacion.mueble?.habitacion?.nombre }} ›
                    {{ juego.ubicacion.mueble?.nombre }} ›
                    {{ juego.ubicacion.nombre }}
                  </template>
                  <template v-else>-</template>
                </td>
                <td>
                  <span v-if="juego.expansiones?.length" class="card-count">
                    {{ juego.expansiones.length }}
                  </span>
                  <span v-else>-</span>
                </td>
              </tr>
              <tr
                v-for="exp in juego.expansiones"
                :key="`exp-${exp.id}`"
                class="fila-expansion"
              >
                <td class="td-imagen"></td>
                <td class="expansion-nombre">
                  <router-link :to="`/juegos/${exp.id}`" class="link">
                    ↳ {{ exp.nombre }}
                  </router-link>
                </td>
                <td>{{ propietariosTexto(exp.propietarios) }}</td>
                <td colspan="4"></td>
              </tr>
            </template>
          </tbody>
        </table>
      </div>
    </template>
  </div>
</template>

<style scoped>
.coleccion-conjunta-view {
  max-width: 1200px;
}

.selector-propietarios {
  background: var(--bg-surface);
  border-radius: 12px;
  padding: 1.5rem;
  margin-bottom: 1.5rem;
  box-shadow: var(--shadow-soft);
  border: 1px solid var(--border-soft);
  display: flex;
  align-items: center;
  gap: 1rem;
  flex-wrap: wrap;
}

.propietarios-chips {
  display: flex;
  gap: 0.5rem;
  flex-wrap: wrap;
  flex: 1;
}

.chip {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
  padding: 0.4rem 0.9rem;
  border-radius: 20px;
  border: 2px solid var(--border-soft);
  background: var(--bg-surface-soft);
  color: var(--text-main);
  font-size: 0.88rem;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s;
}

.chip:hover {
  border-color: var(--primary);
}

.chip-active {
  background: var(--primary);
  color: #fff;
  border-color: var(--primary);
}

.chip-check {
  font-size: 0.75rem;
}

.coleccion-titulo {
  font-size: 1.3rem;
  color: var(--primary);
  margin-bottom: 0.25rem;
}

.coleccion-subtitulo {
  font-size: 0.9rem;
  color: var(--text-muted);
  margin-bottom: 1.25rem;
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

.fila-compartida {
  background: rgba(79, 195, 247, 0.05);
}

.fila-expansion {
  background: var(--bg-surface-soft);
}

.fila-expansion td {
  padding-top: 0.4rem;
  padding-bottom: 0.4rem;
  font-size: 0.88rem;
  color: var(--text-muted);
}

.expansion-nombre {
  padding-left: 2rem !important;
}
</style>
