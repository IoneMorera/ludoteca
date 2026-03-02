<script setup>
import { onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useJuegosStore } from '../stores/juegos'

const route = useRoute()
const router = useRouter()
const juegosStore = useJuegosStore()
const backendUrl = import.meta.env.VITE_BACKEND_URL || 'http://localhost:8000'

onMounted(() => {
  juegosStore.fetchJuego(route.params.id)
})
</script>

<template>
  <div class="detalle-view">
    <button class="btn btn-secondary" @click="router.back()">← Volver</button>

    <div v-if="juegosStore.loading" class="loading">Cargando...</div>

    <div v-else-if="juegosStore.juego" class="detalle-card">
      <div class="detalle-header">
        <img
          v-if="juegosStore.juego.imagen"
          :src="backendUrl + juegosStore.juego.imagen"
          :alt="juegosStore.juego.nombre"
          class="detalle-cover"
        />
        <div>
          <h1>{{ juegosStore.juego.nombre }}</h1>
          <p class="descripcion">{{ juegosStore.juego.descripcion || 'Sin descripción' }}</p>
        </div>
      </div>

      <div class="info-grid">
        <div class="info-item">
          <span class="info-label">Categoría</span>
          <span class="info-value">{{ juegosStore.juego.categoria?.nombre || '-' }}</span>
        </div>
        <div class="info-item">
          <span class="info-label">Jugadores</span>
          <span class="info-value">{{ juegosStore.juego.num_jugadores_min }} – {{ juegosStore.juego.num_jugadores_max }}</span>
        </div>
        <div class="info-item">
          <span class="info-label">Edad mínima</span>
          <span class="info-value">{{ juegosStore.juego.edad_minima }}+</span>
        </div>
        <div class="info-item">
          <span class="info-label">Estado</span>
          <span class="info-value">{{ juegosStore.juego.estado }}</span>
        </div>
        <div class="info-item">
          <span class="info-label">Ubicación</span>
          <span class="info-value">
            <template v-if="juegosStore.juego.ubicacion">
              {{ juegosStore.juego.ubicacion.mueble?.habitacion?.nombre || 'Sin habitación' }}
              ›
              {{ juegosStore.juego.ubicacion.mueble?.nombre || 'Sin mueble' }}
              ›
              {{ juegosStore.juego.ubicacion.nombre }}
            </template>
            <template v-else>
              Sin ubicación asignada
            </template>
          </span>
        </div>
      </div>

      <div v-if="juegosStore.juego.prestamos?.length" class="prestamos-section">
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
            <tr v-for="p in juegosStore.juego.prestamos" :key="p.id">
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
  </div>
</template>

<style scoped>
.detalle-view {
  max-width: 1024px;
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

.prestamos-section {
  margin-top: 1.5rem;
}

.prestamos-section h2 {
  font-size: 1.2rem;
  color: var(--primary);
  margin-bottom: 0.75rem;
}
</style>
