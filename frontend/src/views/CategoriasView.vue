<script setup>
import { ref, onMounted } from 'vue'
import { useCategoriasStore } from '../stores/categorias'
import PageHeader from '../components/PageHeader.vue'
import LoadingState from '../components/LoadingState.vue'
import EmptyState from '../components/EmptyState.vue'
import CardList from '../components/CardList.vue'
import FormModal from '../components/FormModal.vue'

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
    <PageHeader title="Categorías">
      <template #actions>
        <button class="btn btn-primary" @click="abrirFormulario()">+ Nueva Categoría</button>
      </template>
    </PageHeader>

    <LoadingState v-if="store.loading" text="Cargando categorías..." />

    <EmptyState
      v-else-if="store.categorias.length === 0"
      text="No se encontraron categorías."
    />

    <CardList
      v-else
      :items="store.categorias"
      v-slot="{ item: cat }"
    >
      <div class="card">
        <div class="card-info">
          <h3>{{ cat.nombre }}</h3>
          <p class="card-subtext">{{ cat.descripcion || 'Sin descripción' }}</p>
          <span class="card-count">{{ cat.juegos_count || 0 }} juegos</span>
        </div>
        <div class="card-actions">
          <button class="btn btn-sm btn-secondary" @click="abrirFormulario(cat)">Editar</button>
          <button class="btn btn-sm btn-danger" @click="eliminar(cat.id)">Eliminar</button>
        </div>
      </div>
    </CardList>

    <FormModal
      :visible="mostrarFormulario"
      :title="editando ? 'Editar Categoría' : 'Nueva Categoría'"
      @close="mostrarFormulario = false"
    >
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
    </FormModal>
  </div>
</template>

<style scoped>
.cards-grid {
  grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
}
</style>
