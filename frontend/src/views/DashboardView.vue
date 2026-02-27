<script setup>
import { ref, onMounted } from 'vue'
import api from '../api'

const stats = ref({
  totalJuegos: 0,
  juegosDisponibles: 0,
  prestamosActivos: 0,
})
const loading = ref(true)

onMounted(async () => {
  try {
    const { data } = await api.get('/stats')
    stats.value = {
      totalJuegos: data.totalJuegos || 0,
      juegosDisponibles: data.juegosDisponibles || 0,
      prestamosActivos: data.prestamosActivos || 0,
    }
  } catch {
    // Stats will remain at 0
  } finally {
    loading.value = false
  }
})
</script>

<template>
  <div class="dashboard">
    <h1 class="page-title">Panel de Control</h1>

    <div v-if="loading" class="loading">Cargando estadísticas...</div>

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

      <div class="stat-card stat-prestamos">
        <div class="stat-icon">📋</div>
        <div class="stat-info">
          <span class="stat-value">{{ stats.prestamosActivos }}</span>
          <span class="stat-label">Préstamos Activos</span>
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
        <router-link to="/prestamos" class="action-card">
          <span class="action-icon">📋</span>
          <span>Nuevo Préstamo</span>
        </router-link>
        <router-link to="/categorias" class="action-card">
          <span class="action-icon">📂</span>
          <span>Ver Categorías</span>
        </router-link>
      </div>
    </div>
  </div>
</template>

<style scoped>
.dashboard {
  max-width: 1200px;
}

.page-title {
  font-size: 1.8rem;
  color: #1e3a5f;
  margin-bottom: 1.5rem;
}

.loading {
  text-align: center;
  padding: 2rem;
  color: #666;
}

.stats-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
  gap: 1.5rem;
  margin-bottom: 2rem;
}

.stat-card {
  background: #fff;
  border-radius: 12px;
  padding: 1.5rem;
  display: flex;
  align-items: center;
  gap: 1rem;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08);
  border-left: 4px solid;
}

.stat-juegos {
  border-left-color: #4fc3f7;
}
.stat-disponibles {
  border-left-color: #66bb6a;
}
.stat-prestamos {
  border-left-color: #ab47bc;
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
  color: #1e3a5f;
}

.stat-label {
  font-size: 0.85rem;
  color: #888;
}

.quick-actions h2 {
  font-size: 1.3rem;
  color: #1e3a5f;
  margin-bottom: 1rem;
}

.actions-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 1rem;
}

.action-card {
  background: #fff;
  border-radius: 12px;
  padding: 1.5rem;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.75rem;
  text-decoration: none;
  color: #1e3a5f;
  font-weight: 600;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08);
  transition: transform 0.2s, box-shadow 0.2s;
}

.action-card:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.12);
}

.action-icon {
  font-size: 2rem;
}
</style>
