<script setup>
import { ref, onMounted } from 'vue'
import { useHabitacionesStore } from '../stores/habitaciones'

const store = useHabitacionesStore()
const mostrarFormulario = ref(false)
const editando = ref(null)
const form = ref({ nombre: '' })

onMounted(() => {
  store.fetchHabitaciones()
})

function abrirFormulario(habitacion = null) {
  if (habitacion) {
    editando.value = habitacion.id
    form.value = { nombre: habitacion.nombre }
  } else {
    editando.value = null
    form.value = { nombre: '' }
  }
  mostrarFormulario.value = true
}

async function guardar() {
  try {
    if (editando.value) {
      await store.actualizarHabitacion(editando.value, form.value)
    } else {
      await store.crearHabitacion(form.value)
    }
    mostrarFormulario.value = false
  } catch (e) {
    alert(e.response?.data?.message || 'Error al guardar la habitación')
  }
}

async function eliminar(id) {
  if (!confirm('¿Estás seguro de eliminar esta habitación?')) return
  try {
    await store.eliminarHabitacion(id)
  } catch (e) {
    alert(e.response?.data?.message || 'No se puede eliminar: puede tener muebles asociados')
  }
}
</script>

<template>
  <div class="habitaciones-view">
    <div class="page-header">
      <h1 class="page-title">Habitaciones</h1>
      <button class="btn btn-primary" @click="abrirFormulario()">+ Nueva Habitación</button>
    </div>

    <div v-if="store.loading" class="loading">Cargando habitaciones...</div>

    <div v-else class="cards-grid">
      <div v-for="hab in store.habitaciones" :key="hab.id" class="card">
        <div class="card-info">
          <router-link
            :to="{ name: 'juegos', query: { habitacion_id: hab.id } }"
            class="link"
          >
            <h3>{{ hab.nombre }}</h3>
          </router-link>
          <p class="card-subtext">
            {{ hab.muebles_count || 0 }} muebles · {{ hab.juegos_count || 0 }} juegos
          </p>
        </div>
        <div class="card-actions">
          <button class="btn btn-sm btn-secondary" @click="abrirFormulario(hab)">Editar</button>
          <button class="btn btn-sm btn-danger" @click="eliminar(hab.id)">Eliminar</button>
        </div>
      </div>
    </div>

    <div v-if="mostrarFormulario" class="modal-overlay" @click.self="mostrarFormulario = false">
      <div class="modal">
        <h2>{{ editando ? 'Editar Habitación' : 'Nueva Habitación' }}</h2>
        <form @submit.prevent="guardar">
          <div class="form-group">
            <label>Nombre</label>
            <input v-model="form.nombre" type="text" class="input" required />
          </div>
          <div class="form-actions">
            <button type="button" class="btn btn-secondary" @click="mostrarFormulario = false">
              Cancelar
            </button>
            <button type="submit" class="btn btn-primary">
              Guardar
            </button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>

<style scoped>
</style>

