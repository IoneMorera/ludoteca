<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'

const router = useRouter()
const authStore = useAuthStore()

const form = ref({
  email: '',
  password: '',
  remember: false,
})
const errors = ref({})

async function handleLogin() {
  errors.value = {}
  try {
    await authStore.login(form.value)
    router.push('/')
  } catch (e) {
    if (e.response?.data?.errors) {
      errors.value = e.response.data.errors
    }
  }
}
</script>

<template>
  <div class="auth-page">
    <div class="auth-card">
      <div class="auth-header">
        <h1>Ludoteca</h1>
        <p>Inicia sesión en tu cuenta</p>
      </div>

      <form @submit.prevent="handleLogin">
        <div class="form-group">
          <label>Email</label>
          <input
            v-model="form.email"
            type="email"
            class="input"
            required
            autocomplete="email"
            placeholder="tu@email.com"
          />
          <span v-if="errors.email" class="field-error">{{ errors.email[0] }}</span>
        </div>

        <div class="form-group">
          <label>Contraseña</label>
          <input
            v-model="form.password"
            type="password"
            class="input"
            required
            autocomplete="current-password"
            placeholder="••••••••"
          />
          <span v-if="errors.password" class="field-error">{{ errors.password[0] }}</span>
        </div>

        <label class="checkbox-label remember-label">
          <input type="checkbox" v-model="form.remember" />
          Recordarme
        </label>

        <div v-if="authStore.error" class="auth-error">
          {{ authStore.error }}
        </div>

        <button
          type="submit"
          class="btn btn-primary auth-btn"
          :disabled="authStore.loading"
        >
          {{ authStore.loading ? 'Entrando...' : 'Iniciar sesión' }}
        </button>
      </form>

      <p class="auth-switch">
        ¿No tienes cuenta?
        <router-link to="/register">Regístrate</router-link>
      </p>
    </div>
  </div>
</template>

<style scoped>
.auth-page {
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  background: linear-gradient(135deg, #1e3a5f 0%, #2d5a87 50%, #4fc3f7 100%);
  padding: 1rem;
}

.auth-card {
  background: var(--bg-surface);
  border-radius: 16px;
  padding: 2.5rem;
  width: 100%;
  max-width: 420px;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.2);
}

.auth-header {
  text-align: center;
  margin-bottom: 2rem;
}

.auth-header h1 {
  font-size: 2rem;
  color: var(--primary);
  margin-bottom: 0.5rem;
}

.auth-header p {
  color: var(--text-muted);
  font-size: 0.95rem;
}

.auth-btn {
  width: 100%;
  padding: 0.75rem;
  font-size: 1rem;
  margin-top: 0.5rem;
}

.auth-error {
  background: #ffebee;
  color: #c62828;
  padding: 0.6rem 1rem;
  border-radius: 8px;
  font-size: 0.85rem;
  margin-bottom: 0.75rem;
}

.field-error {
  color: #c62828;
  font-size: 0.8rem;
  margin-top: 0.2rem;
  display: block;
}

.remember-label {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  font-size: 0.88rem;
  color: var(--text-muted);
  margin-bottom: 1rem;
  cursor: pointer;
}

.auth-switch {
  text-align: center;
  margin-top: 1.5rem;
  font-size: 0.9rem;
  color: var(--text-muted);
}

.auth-switch a {
  color: var(--primary);
  text-decoration: none;
  font-weight: 600;
}

.auth-switch a:hover {
  text-decoration: underline;
}
</style>
