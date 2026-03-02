import { defineStore } from 'pinia'
import { ref } from 'vue'
import api from '../api'

export const useHabitacionesStore = defineStore('habitaciones', () => {
  const habitaciones = ref([])
  const loading = ref(false)
  const error = ref(null)

  async function fetchHabitaciones() {
    loading.value = true
    error.value = null
    try {
      const { data } = await api.get('/habitaciones')
      habitaciones.value = data
    } catch (e) {
      error.value = e.response?.data?.message || 'Error al cargar habitaciones'
    } finally {
      loading.value = false
    }
  }

  async function crearHabitacion(payload) {
    const { data } = await api.post('/habitaciones', payload)
    habitaciones.value.push(data)
    return data
  }

  async function actualizarHabitacion(id, payload) {
    const { data } = await api.put(`/habitaciones/${id}`, payload)
    const index = habitaciones.value.findIndex((h) => h.id === id)
    if (index !== -1) habitaciones.value[index] = data
    return data
  }

  async function eliminarHabitacion(id) {
    await api.delete(`/habitaciones/${id}`)
    habitaciones.value = habitaciones.value.filter((h) => h.id !== id)
  }

  return {
    habitaciones,
    loading,
    error,
    fetchHabitaciones,
    crearHabitacion,
    actualizarHabitacion,
    eliminarHabitacion,
  }
})

