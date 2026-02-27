import { defineStore } from 'pinia'
import { ref } from 'vue'
import api from '../api'

export const usePrestamosStore = defineStore('prestamos', () => {
  const prestamos = ref([])
  const prestamo = ref(null)
  const pagination = ref({})
  const loading = ref(false)
  const error = ref(null)

  async function fetchPrestamos(params = {}) {
    loading.value = true
    error.value = null
    try {
      const { data } = await api.get('/prestamos', { params })
      prestamos.value = data.data
      pagination.value = {
        total: data.total,
        currentPage: data.current_page,
        lastPage: data.last_page,
        perPage: data.per_page,
      }
    } catch (e) {
      error.value = e.response?.data?.message || 'Error al cargar préstamos'
    } finally {
      loading.value = false
    }
  }

  async function crearPrestamo(datos) {
    const { data } = await api.post('/prestamos', datos)
    prestamos.value.unshift(data)
    return data
  }

  async function devolverPrestamo(id) {
    const { data } = await api.patch(`/prestamos/${id}/devolver`)
    const index = prestamos.value.findIndex((p) => p.id === id)
    if (index !== -1) prestamos.value[index] = data
    return data
  }

  return {
    prestamos,
    prestamo,
    pagination,
    loading,
    error,
    fetchPrestamos,
    crearPrestamo,
    devolverPrestamo,
  }
})
