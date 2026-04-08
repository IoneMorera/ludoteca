import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import api from '../api'

export const useAuthStore = defineStore('auth', () => {
  const user = ref(null)
  const loading = ref(false)
  const error = ref(null)

  const isAuthenticated = computed(() => !!user.value)

  async function fetchUser() {
    try {
      const { data } = await api.get('/api/user')
      user.value = data.user
    } catch {
      user.value = null
    }
  }

  async function login(credentials) {
    loading.value = true
    error.value = null
    try {
      await getCsrfCookie()
      const { data } = await api.post('/api/login', credentials)
      user.value = data.user
      return data
    } catch (e) {
      error.value = e.response?.data?.message || 'Error al iniciar sesión'
      throw e
    } finally {
      loading.value = false
    }
  }

  async function register(datos) {
    loading.value = true
    error.value = null
    try {
      await getCsrfCookie()
      const { data } = await api.post('/api/register', datos)
      user.value = data.user
      return data
    } catch (e) {
      error.value = e.response?.data?.message || 'Error al registrarse'
      throw e
    } finally {
      loading.value = false
    }
  }

  async function logout() {
    try {
      await api.post('/api/logout')
    } finally {
      user.value = null
    }
  }

  async function getCsrfCookie() {
    const backendBase = import.meta.env.VITE_URL || 'http://localhost:8000'
    await api.get('/sanctum/csrf-cookie')
  }

  return {
    user,
    loading,
    error,
    isAuthenticated,
    fetchUser,
    login,
    register,
    logout,
  }
})
