<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import api from '../api'

const route = useRoute()
const router = useRouter()

const plays = ref([])
const total = ref(0)
const loading = ref(true)
const error = ref(null)
const buscar = ref('')
const page = ref(1)

const username = computed(() => route.params.username)

const partidasFiltradas = computed(() => {
  if (!buscar.value) return plays.value
  const query = buscar.value.toLowerCase()
  return plays.value.filter(p => p.game_name.toLowerCase().includes(query))
})

async function fetchPlays() {
  loading.value = true
  error.value = null
  try {
    const { data } = await api.get(`/bgg/plays/${username.value}`, {
      params: { page: page.value },
    })
    plays.value = data.plays
    total.value = data.total
  } catch (e) {
    error.value = e.response?.data?.message || 'Error al cargar las partidas de BGG'
  } finally {
    loading.value = false
  }
}

function prevPage() {
  if (page.value > 1) {
    page.value--
    fetchPlays()
  }
}

function nextPage() {
  page.value++
  fetchPlays()
}

function changeUser() {
  router.push('/bgg')
}

onMounted(fetchPlays)
</script>

<template>
  <div class="plays-view">
    <div class="page-header">
      <div>
        <h1 class="page-title">Partidas BGG</h1>
        <p class="page-subtitle">
          Partidas registradas por <strong>{{ username }}</strong> en BoardGameGeek
          <span v-if="total > 0" class="total-badge">{{ total }} total</span>
        </p>
      </div>
      <div class="header-actions">
        <button class="btn btn-secondary" @click="changeUser">← Cambiar usuario</button>
      </div>
    </div>

    <div v-if="!loading && !error" class="filters">
      <input
        v-model="buscar"
        type="text"
        placeholder="Buscar por nombre de juego..."
        class="input"
      />
    </div>

    <div v-if="loading" class="loading">
      <div class="spinner"></div>
      <p>Cargando partidas...</p>
    </div>

    <div v-else-if="error" class="error-state">
      <p class="error-icon">⚠️</p>
      <p>{{ error }}</p>
      <button class="btn btn-primary" @click="fetchPlays">Reintentar</button>
    </div>

    <div v-else-if="partidasFiltradas.length === 0" class="empty">
      No se encontraron partidas.
    </div>

    <div v-else class="plays-list">
      <div v-for="play in partidasFiltradas" :key="play.id" class="play-card">
        <div class="play-header">
          <a
            :href="`https://boardgamegeek.com/boardgame/${play.game_bgg_id}`"
            target="_blank"
            rel="noopener"
            class="play-game-name"
          >{{ play.game_name }}</a>
          <span class="play-date">{{ play.date }}</span>
        </div>
        <div class="play-details">
          <span v-if="play.quantity > 1" class="play-tag">x{{ play.quantity }}</span>
          <span v-if="play.players.length" class="play-tag">{{ play.players.length }} jugadores</span>
        </div>
        <div v-if="play.players.length" class="play-players">
          <span
            v-for="(player, idx) in play.players"
            :key="idx"
            class="player-chip"
            :class="{ winner: player.win }"
          >
            {{ player.name }}
            <template v-if="player.score"> ({{ player.score }})</template>
            <template v-if="player.win"> ★</template>
          </span>
        </div>
        <p v-if="play.comments" class="play-comments">{{ play.comments }}</p>
      </div>
    </div>

    <div v-if="!loading && !error && plays.length > 0" class="pagination">
      <button class="btn btn-sm btn-secondary" :disabled="page <= 1" @click="prevPage">← Anterior</button>
      <span class="pagination-info">Página {{ page }}</span>
      <button class="btn btn-sm btn-secondary" :disabled="plays.length < 100" @click="nextPage">Siguiente →</button>
    </div>
  </div>
</template>

<style scoped>
.plays-view {
  max-width: 900px;
}

.page-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 1rem;
  margin-bottom: 1.5rem;
}

.header-actions {
  flex-shrink: 0;
}

.page-title {
  font-size: 1.8rem;
  color: #1e3a5f;
}

.page-subtitle {
  color: #888;
  font-size: 0.9rem;
  margin-top: 0.25rem;
}

.total-badge {
  background: #e8ecf1;
  color: #1e3a5f;
  padding: 0.15rem 0.5rem;
  border-radius: 12px;
  font-size: 0.8rem;
  font-weight: 600;
  margin-left: 0.5rem;
}

.filters {
  margin-bottom: 1.5rem;
}

.btn {
  padding: 0.5rem 1rem;
  border: none;
  border-radius: 8px;
  font-size: 0.85rem;
  font-weight: 600;
  cursor: pointer;
  transition: background 0.2s, opacity 0.2s;
  white-space: nowrap;
}

.btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.btn-primary {
  background: #1e3a5f;
  color: #fff;
}

.btn-primary:hover:not(:disabled) {
  background: #16304f;
}

.btn-secondary {
  background: #e8ecf1;
  color: #1e3a5f;
}

.btn-secondary:hover:not(:disabled) {
  background: #dce1e8;
}

.spinner {
  width: 40px;
  height: 40px;
  border: 4px solid #e0e0e0;
  border-top-color: #1e3a5f;
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
  margin: 0 auto 1rem;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}

.error-state {
  text-align: center;
  padding: 3rem;
  background: #fff;
  border-radius: 12px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08);
}

.error-icon {
  font-size: 2.5rem;
  margin-bottom: 0.5rem;
}

.plays-list {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
}

.play-card {
  background: #fff;
  border-radius: 10px;
  padding: 1rem 1.25rem;
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.06);
}

.play-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 0.5rem;
}

.play-game-name {
  font-weight: 700;
  color: #1e3a5f;
  text-decoration: none;
  font-size: 1.05rem;
}

.play-game-name:hover {
  text-decoration: underline;
}

.play-date {
  font-size: 0.8rem;
  color: #999;
  white-space: nowrap;
}

.play-details {
  display: flex;
  gap: 0.5rem;
  margin-bottom: 0.5rem;
}

.play-tag {
  font-size: 0.75rem;
  background: #f0f2f5;
  color: #555;
  padding: 0.15rem 0.5rem;
  border-radius: 6px;
  font-weight: 500;
}

.play-players {
  display: flex;
  flex-wrap: wrap;
  gap: 0.4rem;
  margin-bottom: 0.4rem;
}

.player-chip {
  font-size: 0.8rem;
  background: #eef2f7;
  color: #333;
  padding: 0.2rem 0.6rem;
  border-radius: 12px;
}

.player-chip.winner {
  background: #e8f5e9;
  color: #2e7d32;
  font-weight: 600;
}

.play-comments {
  font-size: 0.85rem;
  color: #666;
  font-style: italic;
  margin-top: 0.4rem;
}

.pagination {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 1rem;
  margin-top: 1.5rem;
}

.pagination-info {
  font-size: 0.85rem;
  color: #888;
  font-weight: 600;
}

@media (max-width: 600px) {
  .page-header {
    flex-direction: column;
  }

  .play-header {
    flex-direction: column;
    align-items: flex-start;
    gap: 0.25rem;
  }
}
</style>
