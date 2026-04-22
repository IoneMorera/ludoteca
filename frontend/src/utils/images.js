const BACKEND_URL = import.meta.env.VITE_BACKEND_URL || 'http://localhost:8000'

export function resolveImageUrl(imagen) {
  if (!imagen) return ''
  if (/^https?:\/\//i.test(imagen)) {
    return imagen
  }
  return BACKEND_URL + imagen
}
