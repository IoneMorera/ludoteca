import { defineStore } from 'pinia'
import { ref } from 'vue'
import api from '../api'

export const useMueblesStore = defineStore('muebles', () => {
  const muebles = ref([])
  const loading = ref(false)
  const error = ref(null)

  async function fetchMuebles(params = {}) {
    loading.value = true
    error.value = null
    try {
      const { data } = await api.get('/muebles', { params })
      muebles.value = data
    } catch (e) {
      error.value = e.response?.data?.message || 'Error al cargar muebles'
    } finally {
      loading.value = false
    }
  }

  async function crearMueble(payload) {
    const { data } = await api.post('/muebles', payload)
    muebles.value.push(data)
    return data
  }

  async function actualizarMueble(id, payload) {
    const { data } = await api.put(`/muebles/${id}`, payload)
    const index = muebles.value.findIndex((m) => m.id === id)
    if (index !== -1) muebles.value[index] = data
    return data
  }

  async function eliminarMueble(id) {
    await api.delete(`/muebles/${id}`)
    muebles.value = muebles.value.filter((m) => m.id !== id)
  }

  return {
    muebles,
    loading,
    error,
    fetchMuebles,
    crearMueble,
    actualizarMueble,
    eliminarMueble,
  }
})

