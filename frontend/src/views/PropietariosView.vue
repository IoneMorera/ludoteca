<script setup>
import { ref, onMounted } from 'vue'
import { usePropietariosStore } from '../stores/propietarios'
import PageHeader from '../components/PageHeader.vue'
import LoadingState from '../components/LoadingState.vue'
import EmptyState from '../components/EmptyState.vue'
import CardList from '../components/CardList.vue'
import FormModal from '../components/FormModal.vue'

const store = usePropietariosStore()
const mostrarFormulario = ref(false)
const editando = ref(null)
const form = ref({ nombre: '', bgg_username: '' })

onMounted(() => {
  store.fetchPropietarios()
})

function abrirFormulario(propietario = null) {
  if (propietario) {
    editando.value = propietario.id
    form.value = { nombre: propietario.nombre, bgg_username: propietario.bgg_username || '' }
  } else {
    editando.value = null
    form.value = { nombre: '', bgg_username: '' }
  }
  mostrarFormulario.value = true
}

async function guardar() {
  try {
    if (editando.value) {
      await store.actualizarPropietario(editando.value, form.value)
    } else {
      await store.crearPropietario(form.value)
    }
    mostrarFormulario.value = false
  } catch (e) {
    alert(e.response?.data?.message || 'Error al guardar')
  }
}

async function eliminar(id) {
  if (!confirm('¿Estás seguro de eliminar este propietario?')) return
  try {
    await store.eliminarPropietario(id)
  } catch (e) {
    alert(e.response?.data?.message || 'Error al eliminar')
  }
}
</script>

<template>
  <div class="propietarios-view">
    <PageHeader title="Propietarios">
      <template #actions>
        <button class="btn btn-primary" @click="abrirFormulario()">+ Nuevo Propietario</button>
      </template>
    </PageHeader>

    <LoadingState v-if="store.loading" text="Cargando propietarios..." />

    <EmptyState
      v-else-if="store.propietarios.length === 0"
      text="No se encontraron propietarios."
    />

    <CardList
      v-else
      :items="store.propietarios"
      v-slot="{ item: prop }"
    >
      <div class="card">
        <div class="card-info">
          <h3>
            {{ prop.nombre }}
            <span v-if="prop.es_principal" class="principal-tag">Principal</span>
          </h3>
          <span v-if="prop.bgg_username" class="bgg-tag">BGG: @{{ prop.bgg_username }}</span>
          <span class="card-count">{{ prop.juegos_count || 0 }} juegos</span>
        </div>
        <div class="card-actions">
          <router-link
            :to="`/colecciones/personal/${prop.id}`"
            class="btn btn-sm btn-primary"
          >
            Ver colección
          </router-link>
          <button class="btn btn-sm btn-secondary" @click="abrirFormulario(prop)">Editar</button>
          <button v-if="!prop.es_principal" class="btn btn-sm btn-danger" @click="eliminar(prop.id)">Eliminar</button>
        </div>
      </div>
    </CardList>

    <FormModal
      :visible="mostrarFormulario"
      :title="editando ? 'Editar Propietario' : 'Nuevo Propietario'"
      @close="mostrarFormulario = false"
    >
      <form @submit.prevent="guardar">
        <div class="form-group">
          <label>Nombre</label>
          <input v-model="form.nombre" type="text" class="input" required />
        </div>
        <div class="form-group">
          <label>Usuario BGG <span class="optional">(opcional)</span></label>
          <input v-model="form.bgg_username" type="text" class="input" placeholder="Nombre de usuario en BoardGameGeek" />
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

.principal-tag {
  display: inline-block;
  font-size: 0.7rem;
  background: #e3f2fd;
  color: #1565c0;
  padding: 0.1rem 0.5rem;
  border-radius: 6px;
  vertical-align: middle;
  margin-left: 0.4rem;
  font-weight: 600;
}

.bgg-tag {
  display: inline-block;
  font-size: 0.78rem;
  color: var(--text-muted);
  background: var(--bg-surface-soft);
  padding: 0.1rem 0.5rem;
  border-radius: 6px;
}

.optional {
  font-size: 0.75rem;
  color: var(--text-muted);
  font-weight: 400;
}
</style>
