<script setup>
import { ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'

const route = useRoute()
const router = useRouter()
const authStore = useAuthStore()
const mobileOpen = ref(false)
const groupOpen = ref({ casa: true })
const theme = ref(localStorage.getItem('theme') || 'light')

const menuItems = [
  { type: 'item', name: 'Home', path: '/', icon: '📊' },
  { type: 'item', name: 'Colecciones', path: '/propietarios', icon: '👥' },
  { type: 'item', name: 'Juegos', path: '/juegos', icon: '🎲' },
  { type: 'item', name: 'Categorías', path: '/categorias', icon: '📂' },
  { type: 'item', name: 'Colecciones Conjuntas', path: '/colecciones/conjunta', icon: '🤝' },
  {
    type: 'group',
    name: 'Casa',
    icon: '🏠',
    groupKey: 'casa',
    children: [
      { name: 'Habitaciones', path: '/habitaciones', icon: '🛋️' },
      { name: 'Muebles', path: '/muebles', icon: '🗄️' },
      { name: 'Ubicaciones', path: '/ubicaciones', icon: '📍' },
    ],
  },
  { type: 'item', name: 'BGG', path: '/bgg', icon: '🌐' },
]

function isActive(path) {
  if (!path) return false
  if (path === '/') return route.path === '/'
  return route.path.startsWith(path)
}

function toggleTheme() {
  theme.value = theme.value === 'light' ? 'dark' : 'light'
  localStorage.setItem('theme', theme.value)
  document.documentElement.setAttribute('data-theme', theme.value)
}

async function handleLogout() {
  await authStore.logout()
  router.push('/login')
}

document.documentElement.setAttribute('data-theme', theme.value)
</script>

<template>
  <button class="mobile-toggle" @click="mobileOpen = !mobileOpen">☰</button>

  <nav class="sidebar" :class="{ open: mobileOpen }">
    <div class="sidebar-header">
      <h1 class="sidebar-title">🎯 Ludoteca de {{ authStore.user?.name || '...' }}</h1>
    </div>

    <ul class="nav-list">
      <li v-for="item in menuItems" :key="item.name">
        <template v-if="item.type === 'item'">
          <router-link
            :to="item.path"
            class="nav-link"
            :class="{ active: isActive(item.path) }"
            @click="mobileOpen = false"
          >
            <span class="nav-icon">{{ item.icon }}</span>
            <span class="nav-text">{{ item.name }}</span>
          </router-link>
        </template>

        <template v-else-if="item.type === 'group'">
          <button
            class="nav-link nav-group"
            :class="{ active: item.children.some((child) => isActive(child.path)), open: groupOpen[item.groupKey] }"
            type="button"
            @click="groupOpen[item.groupKey] = !groupOpen[item.groupKey]"
          >
            <span class="nav-icon">{{ item.icon }}</span>
            <span class="nav-text">{{ item.name }}</span>
            <span class="nav-chevron">{{ groupOpen[item.groupKey] ? '▾' : '▸' }}</span>
          </button>

          <ul v-if="groupOpen[item.groupKey]" class="nav-sublist">
            <li v-for="child in item.children" :key="child.path">
              <router-link
                :to="child.path"
                class="nav-link nav-subitem"
                :class="{ active: isActive(child.path) }"
                @click="mobileOpen = false"
              >
                <span class="nav-icon">{{ child.icon }}</span>
                <span class="nav-text">{{ child.name }}</span>
              </router-link>
            </li>
          </ul>
        </template>
      </li>
    </ul>

    <div class="sidebar-footer">
      <div class="footer-actions">
        <button class="theme-button" type="button" @click="toggleTheme">
          <span class="theme-icon">{{ theme === 'light' ? '🌞' : '🌙' }}</span>
        </button>
        <button v-if="authStore.user" class="logout-button" type="button" @click="handleLogout">
          Cerrar sesión
        </button>
      </div>
    </div>
  </nav>

  <div v-if="mobileOpen" class="overlay" @click="mobileOpen = false"></div>
</template>

<style scoped>
.sidebar {
  position: fixed;
  top: 0;
  left: 0;
  width: 260px;
  height: 100vh;
  background: linear-gradient(135deg, #1e3a5f 0%, #2d5a87 100%);
  color: #fff;
  display: flex;
  flex-direction: column;
  z-index: 100;
  transition: transform 0.3s ease;
}

.sidebar-header {
  padding: 1.5rem;
  border-bottom: 1px solid rgba(255, 255, 255, 0.1);
}

.sidebar-title {
  font-size: 1.2rem;
  font-weight: 700;
  margin: 0;
  line-height: 1.3;
}

.nav-list {
  list-style: none;
  padding: 1rem 0;
  margin: 0;
  flex: 1;
  overflow-y: auto;
  min-height: 0;
}

.nav-link {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding: 0.75rem 1.5rem;
  color: rgba(255, 255, 255, 0.75);
  text-decoration: none;
  transition: all 0.2s ease;
  border-left: 3px solid transparent;
}

.nav-link:hover {
  background: rgba(255, 255, 255, 0.1);
  color: #fff;
}

.nav-link.active {
  background: rgba(255, 255, 255, 0.15);
  color: #fff;
  border-left-color: #4fc3f7;
}

.nav-icon {
  font-size: 1.2rem;
  width: 1.5rem;
  text-align: center;
}

.nav-text {
  font-size: 0.95rem;
}

.nav-group {
  width: 100%;
  background: transparent;
  border: none;
  text-align: left;
  cursor: pointer;
}

.nav-chevron {
  margin-left: auto;
  font-size: 0.8rem;
  opacity: 0.8;
}

.nav-sublist {
  list-style: none;
  margin: 0;
  padding: 0 0 0.25rem;
}

.nav-subitem {
  padding-left: 2.5rem;
  font-size: 0.9rem;
}

.sidebar-footer {
  padding: 0.75rem 1.5rem;
  border-top: 1px solid rgba(255, 255, 255, 0.1);
}

.footer-actions {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.logout-button {
  background: rgba(255, 255, 255, 0.12);
  color: #fff;
  border: none;
  border-radius: 6px;
  padding: 0.3rem 0.7rem;
  font-size: 0.75rem;
  cursor: pointer;
  opacity: 0.8;
  transition: all 0.2s;
}

.logout-button:hover {
  background: rgba(229, 57, 53, 0.7);
  opacity: 1;
}

.theme-button {
  background: rgba(255, 255, 255, 0.12);
  color: #fff;
  border: none;
  border-radius: 999px;
  width: 2rem;
  height: 2rem;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 1rem;
  cursor: pointer;
  transition: background 0.2s;
}

.theme-button:hover {
  background: rgba(255, 255, 255, 0.2);
}

.mobile-toggle {
  display: none;
  position: fixed;
  top: 1rem;
  left: 1rem;
  z-index: 200;
  background: #1e3a5f;
  color: #fff;
  border: none;
  border-radius: 8px;
  padding: 0.5rem 0.75rem;
  font-size: 1.3rem;
  cursor: pointer;
}

.overlay {
  display: none;
}

@media (max-width: 768px) {
  .sidebar {
    transform: translateX(-100%);
  }

  .sidebar.open {
    transform: translateX(0);
  }

  .mobile-toggle {
    display: block;
  }

  .overlay {
    display: block;
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.5);
    z-index: 50;
  }
}
</style>
