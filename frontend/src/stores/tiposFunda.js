import { defineStore } from 'pinia'
import { ref } from 'vue'
import api from '../api'

export const useTiposFundaStore = defineStore('tiposFunda', () => {
  const tiposFunda = ref([])
  const loading = ref(false)
  const error = ref(null)

  async function fetchTiposFunda() {
    loading.value = true
    error.value = null
    try {
      const { data } = await api.get('/tipos-funda')
      tiposFunda.value = data
    } catch (e) {
      error.value = e.response?.data?.message || 'Error al cargar tipos de funda'
    } finally {
      loading.value = false
    }
  }

  async function crearTipoFunda(payload) {
    const { data } = await api.post('/tipos-funda', payload)
    tiposFunda.value.push(data)
    return data
  }

  async function actualizarTipoFunda(id, payload) {
    const { data } = await api.put(`/tipos-funda/${id}`, payload)
    const index = tiposFunda.value.findIndex((tipo) => tipo.id === id)
    if (index !== -1) tiposFunda.value[index] = data
    return data
  }

  async function eliminarTipoFunda(id) {
    await api.delete(`/tipos-funda/${id}`)
    tiposFunda.value = tiposFunda.value.filter((tipo) => tipo.id !== id)
  }

  return {
    tiposFunda,
    loading,
    error,
    fetchTiposFunda,
    crearTipoFunda,
    actualizarTipoFunda,
    eliminarTipoFunda,
  }
})
