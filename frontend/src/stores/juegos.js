import { defineStore } from 'pinia'
import { ref } from 'vue'
import api from '../api'

export const useJuegosStore = defineStore('juegos', () => {
  const juegos = ref([])
  const juego = ref(null)
  const pagination = ref({})
  const loading = ref(false)
  const error = ref(null)

  async function fetchJuegos(params = {}) {
    loading.value = true
    error.value = null
    try {
      const { data } = await api.get('/juegos', { params })
      juegos.value = data.data
      pagination.value = {
        total: data.total,
        currentPage: data.current_page,
        lastPage: data.last_page,
        perPage: data.per_page,
      }
    } catch (e) {
      error.value = e.response?.data?.message || 'Error al cargar juegos'
    } finally {
      loading.value = false
    }
  }

  async function fetchJuego(id) {
    loading.value = true
    error.value = null
    try {
      const { data } = await api.get(`/juegos/${id}`)
      juego.value = data
      return data
    } catch (e) {
      error.value = e.response?.data?.message || 'Error al cargar el juego'
    } finally {
      loading.value = false
    }
  }

  async function crearJuego(datos) {
    const { data } = await api.post('/juegos', datos)
    juegos.value.push(data)
    return data
  }

  async function actualizarJuego(id, datos) {
    const { data } = await api.put(`/juegos/${id}`, datos)
    const index = juegos.value.findIndex((j) => j.id === id)
    if (index !== -1) juegos.value[index] = data
    return data
  }

  async function eliminarJuego(id) {
    await api.delete(`/juegos/${id}`)
    juegos.value = juegos.value.filter((j) => j.id !== id)
  }

  return {
    juegos,
    juego,
    pagination,
    loading,
    error,
    fetchJuegos,
    fetchJuego,
    crearJuego,
    actualizarJuego,
    eliminarJuego,
  }
})
