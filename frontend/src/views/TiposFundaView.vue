<script setup>
import { ref, onMounted } from 'vue'
import { useTiposFundaStore } from '../stores/tiposFunda'
import PageHeader from '../components/PageHeader.vue'
import LoadingState from '../components/LoadingState.vue'
import EmptyState from '../components/EmptyState.vue'
import CardList from '../components/CardList.vue'
import FormModal from '../components/FormModal.vue'

const store = useTiposFundaStore()
const mostrarFormulario = ref(false)
const editando = ref(null)
const form = ref({ nombre: '', ancho_mm: null, alto_mm: null, descripcion: '' })

onMounted(() => {
  store.fetchTiposFunda()
})

function abrirFormulario(tipo = null) {
  if (tipo) {
    editando.value = tipo.id
    form.value = {
      nombre: tipo.nombre,
      ancho_mm: tipo.ancho_mm,
      alto_mm: tipo.alto_mm,
      descripcion: tipo.descripcion || '',
    }
  } else {
    editando.value = null
    form.value = { nombre: '', ancho_mm: null, alto_mm: null, descripcion: '' }
  }
  mostrarFormulario.value = true
}

async function guardar() {
  try {
    if (editando.value) {
      await store.actualizarTipoFunda(editando.value, form.value)
    } else {
      await store.crearTipoFunda(form.value)
    }
    mostrarFormulario.value = false
  } catch (e) {
    alert(e.response?.data?.message || 'Error al guardar el tipo de funda')
  }
}

async function eliminar(id) {
  if (!confirm('¿Estás seguro de eliminar este tipo de funda?')) return
  try {
    await store.eliminarTipoFunda(id)
  } catch (e) {
    alert(e.response?.data?.message || 'No se puede eliminar: está usado por algún juego')
  }
}
</script>

<template>
  <div class="tipos-funda-view">
    <PageHeader title="Fundas">
      <template #actions>
        <button class="btn btn-primary" @click="abrirFormulario()">+ Nuevo Tipo</button>
      </template>
    </PageHeader>

    <LoadingState v-if="store.loading" text="Cargando tipos de funda..." />

    <EmptyState
      v-else-if="store.tiposFunda.length === 0"
      text="No se encontraron tipos de funda."
    />

    <CardList
      v-else
      :items="store.tiposFunda"
      v-slot="{ item: tipo }"
    >
      <div class="card">
        <div class="card-info">
          <h3>{{ tipo.nombre }}</h3>
          <p class="card-subtext">
            {{ tipo.ancho_mm }} x {{ tipo.alto_mm }} mm
          </p>
          <p v-if="tipo.descripcion" class="card-subtext">{{ tipo.descripcion }}</p>
          <span class="card-count">{{ tipo.juegos_count || 0 }} juegos</span>
        </div>
        <div class="card-actions">
          <button class="btn btn-sm btn-secondary" @click="abrirFormulario(tipo)">Editar</button>
          <button class="btn btn-sm btn-danger" @click="eliminar(tipo.id)">Eliminar</button>
        </div>
      </div>
    </CardList>

    <FormModal
      :visible="mostrarFormulario"
      :title="editando ? 'Editar Tipo de Funda' : 'Nuevo Tipo de Funda'"
      @close="mostrarFormulario = false"
    >
      <form @submit.prevent="guardar">
        <div class="form-group">
          <label>Nombre</label>
          <input v-model="form.nombre" type="text" class="input" required />
        </div>
        <div class="form-row">
          <div class="form-group">
            <label>Ancho carta (mm)</label>
            <input v-model.number="form.ancho_mm" type="number" class="input" min="1" required />
          </div>
          <div class="form-group">
            <label>Alto carta (mm)</label>
            <input v-model.number="form.alto_mm" type="number" class="input" min="1" required />
          </div>
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
