<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'
import PageHeader from '../components/PageHeader.vue'

const router = useRouter()
const authStore = useAuthStore()
const customUsername = ref('')

const userCards = computed(() => {
  const cards = []

  if (authStore.user?.bgg_username) {
    cards.push({
      username: authStore.user.bgg_username,
      label: authStore.user.name,
      isSelf: true,
    })
  }

  return cards
})

function goCollection(username) {
  router.push(`/bgg/${username}`)
}

function goPlays(username) {
  router.push(`/bgg/${username}/plays`)
}

function goCustom() {
  const u = customUsername.value.trim()
  if (u) router.push(`/bgg/${u}`)
}
</script>

<template>
  <div class="bgg-select">
    <PageHeader
      title="BoardGameGeek"
      subtitle="Consulta tu colección y partidas de BGG"
    />

    <div class="users-grid">
      <div v-for="card in userCards" :key="card.username" class="user-card user-card-self">
        <span class="user-avatar">🎲</span>
        <span class="user-label">{{ card.label }}</span>
        <span class="user-name">@{{ card.username }}</span>
        <div class="user-actions">
          <button class="btn btn-primary" @click="goCollection(card.username)">Colección</button>
          <button class="btn btn-secondary" @click="goPlays(card.username)">Partidas</button>
        </div>
      </div>

      <div class="user-card user-card-custom">
        <span class="user-avatar">🔍</span>
        <span class="user-label">Otro usuario</span>
        <div class="custom-input-row">
          <input
            v-model="customUsername"
            type="text"
            class="input"
            placeholder="Usuario de BGG..."
            @keyup.enter="goCustom"
          />
        </div>
        <div class="user-actions">
          <button
            class="btn btn-primary"
            :disabled="!customUsername.trim()"
            @click="goCollection(customUsername.trim())"
          >
            Colección
          </button>
          <button
            class="btn btn-secondary"
            :disabled="!customUsername.trim()"
            @click="goPlays(customUsername.trim())"
          >
            Partidas
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.bgg-select {
  max-width: 800px;
}

.users-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 1.5rem;
}

.user-card {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.75rem;
  padding: 2rem;
  background: var(--bg-surface);
  border: 2px solid var(--border-soft);
  border-radius: 16px;
  box-shadow: var(--shadow-soft);
  transition: transform 0.2s, box-shadow 0.2s;
}

.user-card:hover {
  transform: translateY(-4px);
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.12);
}

.user-card-self {
  border-color: var(--primary);
}

.user-avatar {
  font-size: 3rem;
  line-height: 1;
}

.user-label {
  font-size: 1.25rem;
  font-weight: 700;
  color: var(--primary);
}

.user-name {
  font-size: 0.85rem;
  color: var(--text-muted);
}

.user-actions {
  display: flex;
  gap: 0.5rem;
  margin-top: 0.5rem;
}

.custom-input-row {
  width: 100%;
}

.custom-input-row .input {
  text-align: center;
}

@media (max-width: 600px) {
  .users-grid {
    grid-template-columns: 1fr;
  }
}
</style>
