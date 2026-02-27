<script setup>
import { ref, onMounted } from 'vue'
import { useCategoriasStore } from '../stores/categorias'

const store = useCategoriasStore()
const mostrarFormulario = ref(false)
const editando = ref(null)
const form = ref({ nombre: '', descripcion: '' })

onMounted(() => {
  store.fetchCategorias()
})

function abrirFormulario(categoria = null) {
  if (categoria) {
    editando.value = categoria.id
    form.value = { nombre: categoria.nombre, descripcion: categoria.descripcion || '' }
  } else {
    editando.value = null
    form.value = { nombre: '', descripcion: '' }
  }
  mostrarFormulario.value = true
}

async function guardar() {
  try {
    if (editando.value) {
      await store.actualizarCategoria(editando.value, form.value)
    } else {
      await store.crearCategoria(form.value)
    }
    mostrarFormulario.value = false
  } catch (e) {
    alert(e.response?.data?.message || 'Error al guardar')
  }
}

async function eliminar(id) {
  if (!confirm('¿Estás seguro de eliminar esta categoría?')) return
  try {
    await store.eliminarCategoria(id)
  } catch (e) {
    alert(e.response?.data?.message || 'No se puede eliminar: tiene juegos asociados')
  }
}
</script>

<template>
  <div class="categorias-view">
    <div class="page-header">
      <h1 class="page-title">Categorías</h1>
      <button class="btn btn-primary" @click="abrirFormulario()">+ Nueva Categoría</button>
    </div>

    <div v-if="store.loading" class="loading">Cargando categorías...</div>

    <div v-else class="cards-grid">
      <div v-for="cat in store.categorias" :key="cat.id" class="category-card">
        <div class="category-info">
          <h3>{{ cat.nombre }}</h3>
          <p>{{ cat.descripcion || 'Sin descripción' }}</p>
          <span class="count">{{ cat.juegos_count || 0 }} juegos</span>
        </div>
        <div class="category-actions">
          <button class="btn btn-sm btn-secondary" @click="abrirFormulario(cat)">Editar</button>
          <button class="btn btn-sm btn-danger" @click="eliminar(cat.id)">Eliminar</button>
        </div>
      </div>
    </div>

    <div v-if="mostrarFormulario" class="modal-overlay" @click.self="mostrarFormulario = false">
      <div class="modal">
        <h2>{{ editando ? 'Editar Categoría' : 'Nueva Categoría' }}</h2>
        <form @submit.prevent="guardar">
          <div class="form-group">
            <label>Nombre</label>
            <input v-model="form.nombre" type="text" class="input" required />
          </div>
          <div class="form-group">
            <label>Descripción</label>
            <textarea v-model="form.descripcion" class="input" rows="3"></textarea>
          </div>
          <div class="form-actions">
            <button type="button" class="btn btn-secondary" @click="mostrarFormulario = false">Cancelar</button>
            <button type="submit" class="btn btn-primary">Guardar</button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>

<style scoped>
.page-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 1.5rem;
}

.page-title {
  font-size: 1.8rem;
  color: #1e3a5f;
}

.cards-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
  gap: 1rem;
}

.category-card {
  background: #fff;
  border-radius: 12px;
  padding: 1.5rem;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08);
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
}

.category-info h3 {
  color: #1e3a5f;
  margin: 0 0 0.25rem;
}

.category-info p {
  color: #666;
  font-size: 0.9rem;
  margin: 0 0 0.5rem;
}

.count {
  font-size: 0.8rem;
  background: #e3f2fd;
  color: #1565c0;
  padding: 0.2rem 0.6rem;
  border-radius: 12px;
}

.category-actions {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}
</style>
