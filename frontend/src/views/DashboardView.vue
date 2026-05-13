<script setup>
import { computed, ref, onMounted } from 'vue'
import api from '../api'
import PageHeader from '../components/PageHeader.vue'
import LoadingState from '../components/LoadingState.vue'

const stats = ref({
  totalJuegos: 0,
  juegosDisponibles: 0,
  totalExpansiones: 0,
  fundasFaltantes: [],
})
const loading = ref(true)
const mostrarFundasFaltantes = ref(false)
const fundasDesplegadas = ref({})

const totalFundasFaltantes = computed(() => {
  return stats.value.fundasFaltantes.reduce((total, funda) => {
    return total + Number(funda.cantidad_total || 0)
  }, 0)
})

onMounted(async () => {
  try {
    const { data } = await api.get('/stats')
    stats.value = {
      totalJuegos: data.totalJuegos || 0,
      juegosDisponibles: data.juegosDisponibles || 0,
      totalExpansiones: data.totalExpansiones || 0,
      fundasFaltantes: data.fundasFaltantes || [],
    }
  } catch {
    // Stats will remain at 0
  } finally {
    loading.value = false
  }
})

function toggleJuegos(tipoFundaId) {
  fundasDesplegadas.value = {
    ...fundasDesplegadas.value,
    [tipoFundaId]: !fundasDesplegadas.value[tipoFundaId],
  }
}
</script>

<template>
  <div class="dashboard">
    <PageHeader title="Panel de Control" />

    <LoadingState
      v-if="loading"
      text="Cargando estadísticas..."
      :spinner="true"
    />

    <div v-else class="stats-grid">
      <div class="stat-card stat-juegos">
        <div class="stat-icon">🎲</div>
        <div class="stat-info">
          <span class="stat-value">{{ stats.totalJuegos }}</span>
          <span class="stat-label">Total Juegos</span>
        </div>
      </div>

      <div class="stat-card stat-disponibles">
        <div class="stat-icon">✅</div>
        <div class="stat-info">
          <span class="stat-value">{{ stats.juegosDisponibles }}</span>
          <span class="stat-label">Juegos Disponibles</span>
        </div>
      </div>

      <div class="stat-card stat-expansiones">
        <div class="stat-icon">🧩</div>
        <div class="stat-info">
          <span class="stat-value">{{ stats.totalExpansiones }}</span>
          <span class="stat-label">Expansiones</span>
        </div>
      </div>

    </div>

    <div v-if="!loading && stats.fundasFaltantes.length" class="fundas-alert">
      <button
        type="button"
        class="fundas-alert__summary"
        @click="mostrarFundasFaltantes = !mostrarFundasFaltantes"
      >
        <span class="fundas-alert__icon">🃏</span>
        <span>
          <strong>Faltan Fundas</strong>
          <small>{{ totalFundasFaltantes }} fundas pendientes en {{ stats.fundasFaltantes.length }} tamaños</small>
        </span>
        <span class="fundas-alert__chevron">{{ mostrarFundasFaltantes ? '▴' : '▾' }}</span>
      </button>

      <div v-if="mostrarFundasFaltantes" class="fundas-alert__list">
        <div
          v-for="funda in stats.fundasFaltantes"
          :key="funda.tipo_funda_id"
          class="fundas-alert__item"
        >
          <button
            type="button"
            class="fundas-alert__item-header"
            @click="toggleJuegos(funda.tipo_funda_id)"
          >
            <span>
              <strong>{{ funda.nombre || 'Tipo no disponible' }}</strong>
              <small>{{ funda.ancho_mm }} x {{ funda.alto_mm }} mm</small>
            </span>
            <span class="fundas-alert__quantity">{{ funda.cantidad_total }} fundas</span>
            <span>{{ fundasDesplegadas[funda.tipo_funda_id] ? '▴' : '▾' }}</span>
          </button>

          <div
            v-if="fundasDesplegadas[funda.tipo_funda_id]"
            class="fundas-alert__games"
          >
            <router-link
              v-for="juego in funda.juegos"
              :key="juego.id"
              :to="`/juegos/${juego.id}`"
              class="fundas-alert__game"
            >
              <span>{{ juego.nombre || 'Juego no disponible' }}</span>
              <strong>{{ juego.cantidad_cartas }} cartas</strong>
            </router-link>
          </div>
        </div>
      </div>
    </div>

    <div class="quick-actions">
      <h2>Acciones Rápidas</h2>
      <div class="actions-grid">
        <router-link to="/juegos" class="action-card">
          <span class="action-icon">🎲</span>
          <span>Gestionar Juegos</span>
        </router-link>
        <router-link to="/categorias" class="action-card">
          <span class="action-icon">📂</span>
          <span>Ver Categorías</span>
        </router-link>
        <router-link to="/propietarios" class="action-card">
          <span class="action-icon">👥</span>
          <span>Colecciones</span>
        </router-link>
      </div>
    </div>
  </div>
</template>

<style scoped>
.dashboard {
  max-width: 1200px;
}

.stats-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
  gap: 1.5rem;
  margin-bottom: 2rem;
}

.stat-card {
  background: var(--bg-surface);
  border-radius: 12px;
  padding: 1.5rem;
  display: flex;
  align-items: center;
  gap: 1rem;
  box-shadow: var(--shadow-soft);
  border: 1px solid var(--border-soft);
  border-left: 4px solid;
}

.stat-juegos {
  border-left-color: #4fc3f7;
}
.stat-disponibles {
  border-left-color: #66bb6a;
}
.stat-expansiones {
  border-left-color: #ff9800;
}

.fundas-alert {
  background: var(--bg-surface);
  border: 1px solid #f59e0b;
  border-left: 4px solid #f59e0b;
  border-radius: 12px;
  box-shadow: var(--shadow-soft);
  margin-bottom: 2rem;
  overflow: hidden;
}

.fundas-alert__summary,
.fundas-alert__item-header {
  width: 100%;
  display: flex;
  align-items: center;
  gap: 0.75rem;
  background: transparent;
  border: 0;
  color: var(--text-main);
  cursor: pointer;
  text-align: left;
}

.fundas-alert__summary {
  padding: 1rem 1.25rem;
}

.fundas-alert__summary small,
.fundas-alert__item-header small {
  display: block;
  color: var(--text-muted);
  font-size: 0.82rem;
  margin-top: 0.15rem;
}

.fundas-alert__icon {
  font-size: 1.8rem;
}

.fundas-alert__chevron {
  margin-left: auto;
  color: var(--text-muted);
}

.fundas-alert__list {
  border-top: 1px solid var(--border-soft);
}

.fundas-alert__item + .fundas-alert__item {
  border-top: 1px solid var(--border-soft);
}

.fundas-alert__item-header {
  padding: 0.85rem 1.25rem;
}

.fundas-alert__quantity {
  margin-left: auto;
  white-space: nowrap;
  font-weight: 700;
  color: #b45309;
}

.fundas-alert__games {
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
  padding: 0 1.25rem 0.9rem 2.25rem;
}

.fundas-alert__game {
  display: flex;
  justify-content: space-between;
  gap: 0.75rem;
  color: var(--primary);
  font-size: 0.9rem;
  text-decoration: none;
}

.fundas-alert__game:hover {
  text-decoration: underline;
}

.stat-icon {
  font-size: 2.5rem;
}

.stat-info {
  display: flex;
  flex-direction: column;
}

.stat-value {
  font-size: 2rem;
  font-weight: 700;
  color: var(--text-main);
}

.stat-label {
  font-size: 0.85rem;
  color: var(--text-muted);
}

.quick-actions h2 {
  font-size: 1.3rem;
  color: var(--primary);
  margin-bottom: 1rem;
}

.actions-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 1rem;
}

.action-card {
  background: var(--bg-surface);
  border-radius: 12px;
  padding: 1.5rem;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.75rem;
  text-decoration: none;
  color: var(--text-main);
  font-weight: 600;
  box-shadow: var(--shadow-soft);
  border: 1px solid var(--border-soft);
  transition: transform 0.2s, box-shadow 0.2s;
}

.action-card:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.12);
}

.action-icon {
  font-size: 2rem;
}

@media (max-width: 600px) {
  .fundas-alert__summary,
  .fundas-alert__item-header,
  .fundas-alert__game {
    align-items: flex-start;
  }

  .fundas-alert__game {
    flex-direction: column;
    gap: 0.15rem;
  }
}
</style>
