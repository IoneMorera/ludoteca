import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import api from '../api'

const TOKEN_KEY = 'auth_token'

export const useAuthStore = defineStore('auth', () => {
  const user = ref(null)
  const loading = ref(false)
  const error = ref(null)

  const isAuthenticated = computed(() => !!user.value)

  function setToken(token) {
    if (token) {
      localStorage.setItem(TOKEN_KEY, token)
    } else {
      localStorage.removeItem(TOKEN_KEY)
    }
  }

  async function fetchUser() {
    if (!localStorage.getItem(TOKEN_KEY)) {
      user.value = null
      return
    }
    try {
      const { data } = await api.get('/user')
      user.value = data.user
    } catch {
      user.value = null
      setToken(null)
    }
  }

  async function login(credentials) {
    loading.value = true
    error.value = null
    try {
      const { data } = await api.post('/login', credentials)
      setToken(data.token)
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
      const { data } = await api.post('/register', datos)
      setToken(data.token)
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
      await api.post('/logout')
    } finally {
      user.value = null
      setToken(null)
    }
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
