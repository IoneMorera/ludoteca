import { defineStore } from 'pinia'
import { ref } from 'vue'
import api from '../api'

export const useCategoriasStore = defineStore('categorias', () => {
  const categorias = ref([])
  const loading = ref(false)
  const error = ref(null)

  async function fetchCategorias() {
    loading.value = true
    error.value = null
    try {
      const { data } = await api.get('/categorias')
      categorias.value = data
    } catch (e) {
      error.value = e.response?.data?.message || 'Error al cargar categorías'
    } finally {
      loading.value = false
    }
  }

  async function crearCategoria(categoria) {
    const { data } = await api.post('/categorias', categoria)
    categorias.value.push(data)
    return data
  }

  async function actualizarCategoria(id, categoria) {
    const { data } = await api.put(`/categorias/${id}`, categoria)
    const index = categorias.value.findIndex((c) => c.id === id)
    if (index !== -1) categorias.value[index] = data
    return data
  }

  async function eliminarCategoria(id) {
    await api.delete(`/categorias/${id}`)
    categorias.value = categorias.value.filter((c) => c.id !== id)
  }

  return {
    categorias,
    loading,
    error,
    fetchCategorias,
    crearCategoria,
    actualizarCategoria,
    eliminarCategoria,
  }
})
