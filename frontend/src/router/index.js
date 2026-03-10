import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '../stores/auth'

const routes = [
  {
    path: '/login',
    name: 'login',
    component: () => import('../views/LoginView.vue'),
    meta: { title: 'Iniciar Sesión', guest: true },
  },
  {
    path: '/register',
    name: 'register',
    component: () => import('../views/RegisterView.vue'),
    meta: { title: 'Registro', guest: true },
  },
  {
    path: '/',
    name: 'dashboard',
    component: () => import('../views/DashboardView.vue'),
    meta: { title: 'Panel de Control' },
  },
  {
    path: '/juegos',
    name: 'juegos',
    component: () => import('../views/JuegosView.vue'),
    meta: { title: 'Juegos' },
  },
  {
    path: '/juegos/:id',
    name: 'juego-detalle',
    component: () => import('../views/JuegoDetalleView.vue'),
    meta: { title: 'Detalle del Juego' },
  },
  {
    path: '/categorias',
    name: 'categorias',
    component: () => import('../views/CategoriasView.vue'),
    meta: { title: 'Categorías' },
  },
  {
    path: '/prestamos',
    name: 'prestamos',
    component: () => import('../views/PrestamosView.vue'),
    meta: { title: 'Préstamos' },
  },
  {
    path: '/propietarios',
    name: 'propietarios',
    component: () => import('../views/PropietariosView.vue'),
    meta: { title: 'Propietarios' },
  },
  {
    path: '/colecciones/personal/:id',
    name: 'coleccion-personal',
    component: () => import('../views/ColeccionPersonalView.vue'),
    meta: { title: 'Colección Personal' },
  },
  {
    path: '/colecciones/conjunta',
    name: 'coleccion-conjunta',
    component: () => import('../views/ColeccionConjuntaView.vue'),
    meta: { title: 'Colección Conjunta' },
  },
  {
    path: '/habitaciones',
    name: 'habitaciones',
    component: () => import('../views/HabitacionesView.vue'),
    meta: { title: 'Habitaciones' },
  },
  {
    path: '/muebles',
    name: 'muebles',
    component: () => import('../views/MueblesView.vue'),
    meta: { title: 'Muebles' },
  },
  {
    path: '/ubicaciones',
    name: 'ubicaciones',
    component: () => import('../views/UbicacionesView.vue'),
    meta: { title: 'Ubicaciones' },
  },
  {
    path: '/bgg',
    name: 'bgg',
    component: () => import('../views/BggUserSelectView.vue'),
    meta: { title: 'Colección BGG' },
  },
  {
    path: '/bgg/:username',
    name: 'bgg-collection',
    component: () => import('../views/BggCollectionView.vue'),
    meta: { title: 'Colección BGG' },
  },
  {
    path: '/bgg/:username/plays',
    name: 'bgg-plays',
    component: () => import('../views/BggPlaysView.vue'),
    meta: { title: 'Partidas BGG' },
  },
]

const router = createRouter({
  history: createWebHistory(),
  routes,
})

router.beforeEach(async (to) => {
  document.title = `${to.meta.title || 'Ludoteca'} | Ludoteca`

  const authStore = useAuthStore()

  if (!authStore.user && !to.meta.guest) {
    try {
      await authStore.fetchUser()
    } catch {
      // ignore
    }
  }

  if (!authStore.isAuthenticated && !to.meta.guest) {
    return { name: 'login' }
  }

  if (authStore.isAuthenticated && to.meta.guest) {
    return { name: 'dashboard' }
  }
})

export default router
