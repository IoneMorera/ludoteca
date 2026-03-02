<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import api from '../api'
import PageHeader from '../components/PageHeader.vue'
import FilterBar from '../components/FilterBar.vue'
import LoadingState from '../components/LoadingState.vue'
import EmptyState from '../components/EmptyState.vue'
import ErrorState from '../components/ErrorState.vue'

const route = useRoute()
const router = useRouter()

const games = ref([])
const loading = ref(true)
const error = ref(null)
const buscar = ref('')
const importing = ref(false)
const importResult = ref(null)
const username = computed(() => route.params.username)
const subtitle = computed(
  () => `Juegos del usuario ${username.value} en BoardGameGeek`,
)

const juegosFiltrados = computed(() => {
  if (!buscar.value) return games.value
  const query = buscar.value.toLowerCase()
  return games.value.filter((g) => g.name.toLowerCase().includes(query))
})

async function fetchCollection() {
  loading.value = true
  error.value = null
  importResult.value = null
  try {
    const { data } = await api.get(`/bgg/collection/${username.value}`)
    games.value = data.games
  } catch (e) {
    error.value = e.response?.data?.message || 'Error al conectar con BGG'
  } finally {
    loading.value = false
  }
}

async function importGames() {
  if (importing.value || games.value.length === 0) return
  importing.value = true
  importResult.value = null
  try {
    const { data } = await api.post('/bgg/import', { games: games.value })
    importResult.value = data
  } catch {
    importResult.value = { error: 'Error al importar los juegos' }
  } finally {
    importing.value = false
  }
}

function changeUser() {
  router.push('/bgg')
}

function ratingColor(rating) {
  if (rating >= 8) return 'rating-high'
  if (rating >= 6.5) return 'rating-mid'
  if (rating > 0) return 'rating-low'
  return 'rating-none'
}

onMounted(fetchCollection)
</script>

<template>
  <div class="bgg-view">
    <PageHeader :title="'Colección BGG'" :subtitle="subtitle">
      <template #actions>
        <button class="btn btn-secondary" @click="changeUser">← Cambiar usuario</button>
        <button
          v-if="!loading && !error && games.length > 0"
          class="btn btn-primary"
          :disabled="importing"
          @click="importGames"
        >
          {{ importing ? 'Importando...' : 'Añadir juegos a la BBDD' }}
        </button>
      </template>
    </PageHeader>

    <div
      v-if="importResult"
      class="import-feedback"
      :class="importResult.error ? 'import-error' : 'import-success'"
    >
      <template v-if="importResult.error">{{ importResult.error }}</template>
      <template v-else>
        ✔ {{ importResult.imported }} juego(s) importado(s), {{ importResult.skipped }} ya existían en la BBDD
      </template>
      <button class="dismiss-btn" @click="importResult = null">✕</button>
    </div>

    <FilterBar v-if="!loading && !error">
      <input
        v-model="buscar"
        type="text"
        placeholder="Buscar en la colección..."
        class="input"
      />
      <span class="result-count">{{ juegosFiltrados.length }} juegos</span>
    </FilterBar>

    <LoadingState
      v-if="loading"
      text="Cargando colección de BGG..."
      :spinner="true"
      hint="La primera carga puede tardar unos segundos"
    />

    <ErrorState
      v-else-if="error"
      :message="error"
      @retry="fetchCollection"
    />

    <EmptyState
      v-else-if="juegosFiltrados.length === 0"
      text="No se encontraron juegos."
    />

    <div v-else class="games-grid">
      <div v-for="game in juegosFiltrados" :key="game.bgg_id" class="game-card">
        <div class="game-thumb">
          <img
            v-if="game.thumbnail"
            :src="game.thumbnail"
            :alt="game.name"
            loading="lazy"
          />
          <div v-else class="no-image">🎲</div>
        </div>
        <div class="game-info">
          <h3 class="game-name">{{ game.name }}</h3>
          <span v-if="game.year" class="game-year">{{ game.year }}</span>
          <div class="game-meta">
            <span v-if="game.min_players" class="meta-item" title="Jugadores">
              👥 {{ game.min_players }}<template v-if="game.max_players && game.max_players !== game.min_players">–{{ game.max_players }}</template>
            </span>
            <span v-if="game.playing_time" class="meta-item" title="Tiempo de juego">
              ⏱️ {{ game.playing_time }} min
            </span>
            <span v-if="game.num_plays" class="meta-item" title="Partidas jugadas">
              🎯 {{ game.num_plays }} partidas
            </span>
          </div>
          <div class="game-footer">
            <span class="rating-badge" :class="ratingColor(game.rating)">
              ★ {{ game.rating > 0 ? game.rating : '–' }}
            </span>
            <a
              :href="`https://boardgamegeek.com/boardgame/${game.bgg_id}`"
              target="_blank"
              rel="noopener"
              class="bgg-link"
            >Ver en BGG</a>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.bgg-view {
  max-width: 1200px;
}

.page-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 1rem;
  margin-bottom: 1.5rem;
}

.header-actions {
  display: flex;
  gap: 0.75rem;
  flex-shrink: 0;
}

.import-feedback {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0.75rem 1rem;
  border-radius: 8px;
  margin-bottom: 1.25rem;
  font-size: 0.9rem;
  font-weight: 500;
}

.import-success {
  background: #e8f5e9;
  color: #2e7d32;
}

.import-error {
  background: #ffebee;
  color: #c62828;
}

.dismiss-btn {
  background: none;
  border: none;
  cursor: pointer;
  font-size: 1rem;
  opacity: 0.6;
  padding: 0 0.25rem;
  color: inherit;
}

.dismiss-btn:hover {
  opacity: 1;
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

.filters {
  display: flex;
  align-items: center;
  gap: 1rem;
  margin-bottom: 1.5rem;
}

.filters .input {
  flex: 1;
}

.result-count {
  white-space: nowrap;
  color: #888;
  font-size: 0.85rem;
  font-weight: 600;
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

.loading-hint {
  font-size: 0.8rem;
  color: #aaa;
  margin-top: 0.5rem;
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

.error-state p {
  color: #666;
  margin-bottom: 1rem;
}

.games-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 1.25rem;
}

.game-card {
  background: #fff;
  border-radius: 12px;
  overflow: hidden;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08);
  display: flex;
  flex-direction: column;
  transition: transform 0.2s, box-shadow 0.2s;
}

.game-card:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.12);
}

.game-thumb {
  height: 180px;
  background: #f0f2f5;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
}

.game-thumb img {
  width: 100%;
  height: 100%;
  object-fit: contain;
  padding: 0.5rem;
}

.no-image {
  font-size: 3rem;
  opacity: 0.3;
}

.game-info {
  padding: 1rem;
  display: flex;
  flex-direction: column;
  flex: 1;
}

.game-name {
  font-size: 1rem;
  font-weight: 700;
  color: #1e3a5f;
  margin-bottom: 0.15rem;
  line-height: 1.3;
}

.game-year {
  font-size: 0.8rem;
  color: #aaa;
  margin-bottom: 0.5rem;
}

.game-meta {
  display: flex;
  flex-wrap: wrap;
  gap: 0.6rem;
  margin-bottom: 0.75rem;
}

.meta-item {
  font-size: 0.8rem;
  color: #666;
  white-space: nowrap;
}

.game-footer {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-top: auto;
  padding-top: 0.75rem;
  border-top: 1px solid #f0f0f0;
}

.rating-badge {
  font-weight: 700;
  font-size: 0.85rem;
  padding: 0.2rem 0.6rem;
  border-radius: 6px;
}

.rating-high {
  background: #e8f5e9;
  color: #2e7d32;
}

.rating-mid {
  background: #fff3e0;
  color: #e65100;
}

.rating-low {
  background: #ffebee;
  color: #c62828;
}

.rating-none {
  background: #f5f5f5;
  color: #999;
}

.bgg-link {
  font-size: 0.8rem;
  color: #2d5a87;
  text-decoration: none;
  font-weight: 600;
}

.bgg-link:hover {
  text-decoration: underline;
}

@media (max-width: 600px) {
  .page-header {
    flex-direction: column;
  }

  .header-actions {
    width: 100%;
    flex-direction: column;
  }

  .games-grid {
    grid-template-columns: 1fr;
  }

  .filters {
    flex-direction: column;
    align-items: stretch;
  }

  .result-count {
    text-align: center;
  }
}
</style>
