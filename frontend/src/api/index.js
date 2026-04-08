import axios from 'axios'

const api = axios.create({
  baseURL: import.meta.env.VITE_URL || 'http://localhost:8000/',
  headers: {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  },
  withCredentials: true,
  withXSRFToken: true,
})

api.interceptors.response.use(
  (response) => response,
  (error) => {
    const message = error.response?.data?.message || 'Error de conexión con el servidor'
    console.error('API Error:', message)
    return Promise.reject(error)
  }
)

export default api
