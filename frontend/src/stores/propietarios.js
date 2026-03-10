import { defineStore } from 'pinia'
import { ref } from 'vue'
import api from '../api'

export const usePropietariosStore = defineStore('propietarios', () => {
  const propietarios = ref([])
  const propietario = ref(null)
  const coleccion = ref(null)
  const coleccionConjunta = ref(null)
  const loading = ref(false)
  const error = ref(null)

  async function fetchPropietarios() {
    loading.value = true
    error.value = null
    try {
      const { data } = await api.get('/propietarios')
      propietarios.value = data
    } catch (e) {
      error.value = e.response?.data?.message || 'Error al cargar propietarios'
    } finally {
      loading.value = false
    }
  }

  async function fetchPropietario(id) {
    loading.value = true
    error.value = null
    try {
      const { data } = await api.get(`/propietarios/${id}`)
      propietario.value = data
      return data
    } catch (e) {
      error.value = e.response?.data?.message || 'Error al cargar el propietario'
    } finally {
      loading.value = false
    }
  }

  async function crearPropietario(datos) {
    const { data } = await api.post('/propietarios', datos)
    propietarios.value.push(data)
    return data
  }

  async function actualizarPropietario(id, datos) {
    const { data } = await api.put(`/propietarios/${id}`, datos)
    const index = propietarios.value.findIndex((p) => p.id === id)
    if (index !== -1) propietarios.value[index] = data
    return data
  }

  async function eliminarPropietario(id) {
    await api.delete(`/propietarios/${id}`)
    propietarios.value = propietarios.value.filter((p) => p.id !== id)
  }

  async function fetchColeccion(propietarioId) {
    loading.value = true
    error.value = null
    try {
      const { data } = await api.get(`/propietarios/${propietarioId}/coleccion`)
      coleccion.value = data
      return data
    } catch (e) {
      error.value = e.response?.data?.message || 'Error al cargar la colección'
    } finally {
      loading.value = false
    }
  }

  async function fetchColeccionConjunta(propietarioIds) {
    loading.value = true
    error.value = null
    try {
      const { data } = await api.post('/colecciones/conjunta', {
        propietario_ids: propietarioIds,
      })
      coleccionConjunta.value = data
      return data
    } catch (e) {
      error.value = e.response?.data?.message || 'Error al cargar la colección conjunta'
    } finally {
      loading.value = false
    }
  }

  return {
    propietarios,
    propietario,
    coleccion,
    coleccionConjunta,
    loading,
    error,
    fetchPropietarios,
    fetchPropietario,
    crearPropietario,
    actualizarPropietario,
    eliminarPropietario,
    fetchColeccion,
    fetchColeccionConjunta,
  }
})
