import { createRouter, createWebHistory } from 'vue-router'

const routes = [
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

router.beforeEach((to) => {
  document.title = `${to.meta.title || 'Ludoteca'} | Ludoteca`
})

export default router
