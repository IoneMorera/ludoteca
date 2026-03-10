<script setup>
import { onMounted, computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { usePropietariosStore } from '../stores/propietarios'
import PageHeader from '../components/PageHeader.vue'
import LoadingState from '../components/LoadingState.vue'
import EmptyState from '../components/EmptyState.vue'
import StatusBadge from '../components/StatusBadge.vue'

const route = useRoute()
const router = useRouter()
const store = usePropietariosStore()
const backendUrl = import.meta.env.VITE_BACKEND_URL || 'http://localhost:8000'

onMounted(() => {
  store.fetchColeccion(route.params.id)
})

const juegos = computed(() => store.coleccion?.juegos || [])
const propietario = computed(() => store.coleccion?.propietario || null)

function propietariosTexto(props) {
  if (!props || props.length === 0) return '-'
  return props.map((p) => p.nombre).join(', ')
}

function esCompartido(juego) {
  return juego.propietarios && juego.propietarios.length > 1
}
</script>

<template>
  <div class="coleccion-view">
    <button class="btn btn-secondary" @click="router.back()">← Volver</button>

    <PageHeader :title="`Colección de ${propietario?.nombre || '...'}`">
      <template #subtitle>
        {{ juegos.length }} juegos en total
      </template>
    </PageHeader>

    <LoadingState v-if="store.loading" text="Cargando colección..." />

    <EmptyState
      v-else-if="juegos.length === 0"
      text="Esta colección no tiene juegos."
    />

    <div v-else>
      <div class="table-container">
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
    </div>
  </div>
</template>

<style scoped>
.coleccion-view {
  max-width: 1200px;
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
