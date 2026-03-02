import { defineStore } from 'pinia'
import { ref } from 'vue'
import api from '../api'

export const useUbicacionesStore = defineStore('ubicaciones', () => {
  const ubicaciones = ref([])
  const loading = ref(false)
  const error = ref(null)

  async function fetchUbicaciones() {
    loading.value = true
    error.value = null
    try {
      const { data } = await api.get('/ubicaciones')
      ubicaciones.value = data
    } catch (e) {
      error.value = e.response?.data?.message || 'Error al cargar ubicaciones'
    } finally {
      loading.value = false
    }
  }

  async function crearUbicacion(payload) {
    const { data } = await api.post('/ubicaciones', payload)
    ubicaciones.value.unshift(data)
    return data
  }

  return {
    ubicaciones,
    loading,
    error,
    fetchUbicaciones,
    crearUbicacion,
  }
})

