<script setup>
import { useRouter } from 'vue-router'
import PageHeader from '../components/PageHeader.vue'

const router = useRouter()

const users = [
  { username: 'raxar', label: 'Raxar' },
  { username: 'almu_cali', label: 'Almu Cali' },
]

function goCollection(username) {
  router.push(`/bgg/${username}`)
}

function goPlays(username) {
  router.push(`/bgg/${username}/plays`)
}
</script>

<template>
  <div class="bgg-select">
    <PageHeader
      title="BoardGameGeek"
      subtitle="Selecciona un usuario y qué quieres consultar"
    />

    <div class="users-grid">
      <div v-for="user in users" :key="user.username" class="user-card">
        <span class="user-avatar">🎲</span>
        <span class="user-label">{{ user.label }}</span>
        <span class="user-name">@{{ user.username }}</span>
        <div class="user-actions">
          <button class="btn btn-primary" @click="goCollection(user.username)">Colección</button>
          <button class="btn btn-secondary" @click="goPlays(user.username)">Partidas</button>
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
  grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
  gap: 1.5rem;
}

.user-card {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.75rem;
  padding: 2rem;
  background: #fff;
  border: 2px solid transparent;
  border-radius: 16px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08);
  transition: transform 0.2s, box-shadow 0.2s;
}

.user-card:hover {
  transform: translateY(-4px);
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.12);
}

.user-avatar {
  font-size: 3rem;
  line-height: 1;
}

.user-label {
  font-size: 1.25rem;
  font-weight: 700;
  color: #1e3a5f;
}

.user-name {
  font-size: 0.85rem;
  color: #999;
}

.user-actions {
  display: flex;
  gap: 0.5rem;
  margin-top: 0.5rem;
}

@media (max-width: 600px) {
  .users-grid {
    grid-template-columns: 1fr;
  }
}
</style>
