<script setup>
const model = defineModel({ type: Array, default: () => [] })

const props = defineProps({
  tiposFunda: {
    type: Array,
    default: () => [],
  },
})

function addFunda() {
  model.value = [
    ...model.value,
    {
      tipo_funda_id: '',
      cantidad_cartas: null,
      enfundadas: false,
    },
  ]
}

function removeFunda(index) {
  model.value = model.value.filter((_, currentIndex) => currentIndex !== index)
}

function isTipoSelected(tipoId, currentIndex) {
  return model.value.some((funda, index) => {
    return index !== currentIndex && Number(funda.tipo_funda_id) === Number(tipoId)
  })
}
</script>

<template>
  <div class="fundas-editor">
    <div class="fundas-editor__header">
      <div>
        <label>Cartas y fundas</label>
        <p class="fundas-editor__help">
          Indica cuántas cartas lleva el juego de cada tamaño y si ya están enfundadas.
        </p>
      </div>
      <button
        type="button"
        class="btn btn-sm btn-secondary"
        :disabled="tiposFunda.length === 0"
        @click="addFunda"
      >
        + Añadir tamaño
      </button>
    </div>

    <p v-if="tiposFunda.length === 0" class="fundas-editor__empty">
      Primero crea algún tipo de funda en la sección Fundas.
    </p>

    <div v-else-if="model.length === 0" class="fundas-editor__empty">
      No se han indicado cartas para este juego.
    </div>

    <div
      v-for="(funda, index) in model"
      v-else
      :key="index"
      class="fundas-editor__row"
    >
      <select v-model.number="funda.tipo_funda_id" class="input" required>
        <option value="" disabled>Tipo de funda</option>
        <option
          v-for="tipo in tiposFunda"
          :key="tipo.id"
          :value="tipo.id"
          :disabled="isTipoSelected(tipo.id, index)"
        >
          {{ tipo.nombre }} ({{ tipo.ancho_mm }} x {{ tipo.alto_mm }} mm)
        </option>
      </select>

      <input
        v-model.number="funda.cantidad_cartas"
        type="number"
        class="input fundas-editor__quantity"
        min="1"
        placeholder="Cartas"
        required
      />

      <label class="fundas-editor__checkbox">
        <input v-model="funda.enfundadas" type="checkbox" />
        Enfundadas
      </label>

      <button
        type="button"
        class="btn btn-sm btn-danger"
        @click="removeFunda(index)"
      >
        Quitar
      </button>
    </div>
  </div>
</template>

<style scoped>
.fundas-editor {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
}

.fundas-editor__header {
  display: flex;
  gap: 1rem;
  align-items: flex-start;
  justify-content: space-between;
}

.fundas-editor__header label {
  display: block;
  margin-bottom: 0.15rem;
}

.fundas-editor__help,
.fundas-editor__empty {
  margin: 0;
  color: var(--text-muted);
  font-size: 0.85rem;
}

.fundas-editor__row {
  display: grid;
  grid-template-columns: minmax(180px, 1fr) 110px auto auto;
  gap: 0.5rem;
  align-items: center;
}

.fundas-editor__quantity {
  min-width: 0;
}

.fundas-editor__checkbox {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
  font-size: 0.9rem;
  color: var(--text-main);
  white-space: nowrap;
}

@media (max-width: 700px) {
  .fundas-editor__header,
  .fundas-editor__row {
    display: flex;
    flex-direction: column;
    align-items: stretch;
  }
}
</style>
