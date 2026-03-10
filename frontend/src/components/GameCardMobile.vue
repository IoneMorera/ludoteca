<script setup>
import StatusBadge from './StatusBadge.vue'
import { formatDate } from '../utils/format'

const props = defineProps({
  juego: { type: Object, required: true },
  backendUrl: { type: String, default: '' },
  showJugadores: { type: Boolean, default: false },
  showFechaCompra: { type: Boolean, default: false },
  showUbicacion: { type: Boolean, default: true },
  showExpansiones: { type: Boolean, default: true },
})

function propietariosTexto(propietarios) {
  if (!propietarios?.length) return '-'
  return propietarios.map((p) => p.nombre).join(', ')
}

function esCompartido(juego) {
  return juego.propietarios && juego.propietarios.length > 1
}
</script>

<template>
  <div class="gcm" :class="{ 'gcm--compartido': esCompartido(juego) }">
    <div class="gcm__header">
      <img
        v-if="juego.imagen"
        :src="backendUrl + juego.imagen"
        :alt="juego.nombre"
        class="gcm__thumb"
      />
      <span v-else class="gcm__no-thumb">🎲</span>
      <div class="gcm__title-area">
        <router-link :to="`/juegos/${juego.id}`" class="gcm__name">
          {{ juego.nombre }}
        </router-link>
        <span v-if="juego.juego_base_id" class="gcm__expansion-tag">Expansión</span>
      </div>
    </div>

    <div class="gcm__body">
      <div class="gcm__row">
        <span class="gcm__label">Propietarios</span>
        <span class="gcm__value">
          <span v-if="esCompartido(juego)" class="badge badge-info gcm__badge">Compartido</span>
          {{ propietariosTexto(juego.propietarios) }}
        </span>
      </div>

      <div class="gcm__row-inline">
        <div class="gcm__field">
          <span class="gcm__label">Categoría</span>
          <span class="gcm__value">{{ juego.categoria?.nombre || '-' }}</span>
        </div>
        <div class="gcm__field">
          <span class="gcm__label">Estado</span>
          <span class="gcm__value"><StatusBadge :value="juego.estado" type="juego" /></span>
        </div>
      </div>

      <div v-if="showJugadores" class="gcm__row-inline">
        <div class="gcm__field">
          <span class="gcm__label">Jugadores</span>
          <span class="gcm__value">{{ juego.num_jugadores_min }}–{{ juego.num_jugadores_max }}</span>
        </div>
        <div class="gcm__field">
          <span class="gcm__label">Edad</span>
          <span class="gcm__value">{{ juego.edad_minima }}+</span>
        </div>
      </div>

      <div v-if="showFechaCompra && juego.fecha_compra" class="gcm__row">
        <span class="gcm__label">Fecha compra</span>
        <span class="gcm__value">{{ formatDate(juego.fecha_compra) }}</span>
      </div>

      <div v-if="showUbicacion && juego.ubicacion" class="gcm__row">
        <span class="gcm__label">Ubicación</span>
        <span class="gcm__value">
          {{ juego.ubicacion.mueble?.habitacion?.nombre }} ›
          {{ juego.ubicacion.mueble?.nombre }} ›
          {{ juego.ubicacion.nombre }}
        </span>
      </div>

      <div v-if="showExpansiones && juego.expansiones?.length" class="gcm__expansiones">
        <span class="gcm__label">Expansiones ({{ juego.expansiones.length }})</span>
        <div class="gcm__exp-list">
          <router-link
            v-for="exp in juego.expansiones"
            :key="exp.id"
            :to="`/juegos/${exp.id}`"
            class="gcm__exp-item"
          >
            ↳ {{ exp.nombre }}
          </router-link>
        </div>
      </div>
    </div>

    <div v-if="$slots.actions" class="gcm__actions">
      <slot name="actions" />
    </div>
  </div>
</template>

<style scoped>
.gcm {
  background: var(--bg-surface);
  border-radius: 12px;
  box-shadow: var(--shadow-soft);
  border: 1px solid var(--border-soft);
  overflow: hidden;
}

.gcm--compartido {
  border-left: 3px solid #4fc3f7;
}

.gcm__header {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding: 0.85rem 1rem;
  background: var(--bg-surface-soft);
  border-bottom: 1px solid var(--border-soft);
}

.gcm__thumb {
  width: 48px;
  height: 48px;
  object-fit: cover;
  border-radius: 8px;
  flex-shrink: 0;
}

.gcm__no-thumb {
  width: 48px;
  height: 48px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 1.5rem;
  opacity: 0.3;
  flex-shrink: 0;
}

.gcm__title-area {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.4rem;
  min-width: 0;
}

.gcm__name {
  color: var(--primary);
  text-decoration: none;
  font-weight: 700;
  font-size: 0.95rem;
  line-height: 1.3;
}

.gcm__name:hover {
  text-decoration: underline;
}

.gcm__expansion-tag {
  display: inline-block;
  font-size: 0.68rem;
  background: #e3f2fd;
  color: #1565c0;
  padding: 0.1rem 0.4rem;
  border-radius: 6px;
  font-weight: 600;
}

.gcm__body {
  padding: 0.75rem 1rem;
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}

.gcm__row {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  gap: 0.5rem;
}

.gcm__row-inline {
  display: flex;
  gap: 1rem;
}

.gcm__field {
  flex: 1;
  display: flex;
  flex-direction: column;
}

.gcm__label {
  font-size: 0.72rem;
  font-weight: 600;
  color: var(--text-muted);
  text-transform: uppercase;
  letter-spacing: 0.3px;
}

.gcm__value {
  font-size: 0.88rem;
  color: var(--text-main);
}

.gcm__badge {
  margin-right: 0.35rem;
  vertical-align: middle;
}

.gcm__expansiones {
  padding-top: 0.25rem;
}

.gcm__exp-list {
  display: flex;
  flex-direction: column;
  gap: 0.15rem;
  padding-top: 0.25rem;
  padding-left: 0.5rem;
}

.gcm__exp-item {
  font-size: 0.82rem;
  color: var(--primary-soft);
  text-decoration: none;
}

.gcm__exp-item:hover {
  text-decoration: underline;
}

.gcm__actions {
  display: flex;
  gap: 0.5rem;
  padding: 0.65rem 1rem;
  border-top: 1px solid var(--border-soft);
  background: var(--bg-surface-soft);
}

[data-theme='dark'] .gcm__expansion-tag {
  background: #0b2e4a;
  color: #bfdbfe;
}
</style>
