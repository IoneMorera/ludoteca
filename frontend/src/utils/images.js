const BACKEND_URL = import.meta.env.VITE_BACKEND_URL || 'http://localhost:8000'

const BGG_CDN = /(?:^https?:)?\/\/(?:[^/]*\.)?(?:geekdo-images\.com|geekdo\.com)\//i

export function isBggCdn(url) {
  return !!url && BGG_CDN.test(url)
}

function extensionOf(sourceUrl) {
  if (!sourceUrl) return 'jpg'
  try {
    const path = new URL(sourceUrl, 'https://placeholder.local').pathname
    const ext = (path.split('.').pop() || '').toLowerCase()
    if (['jpg', 'jpeg', 'png', 'webp', 'gif'].includes(ext)) {
      return ext === 'jpeg' ? 'jpg' : ext
    }
  } catch (_) {
    /* ignore */
  }
  return 'jpg'
}

export function canonicalizeImage(imagen, bggId) {
  if (!imagen) return ''
  if (!isBggCdn(imagen)) return imagen
  if (!bggId) return ''
  return `/storage/juegos/bgg_${bggId}.${extensionOf(imagen)}`
}

export function resolveImageUrl(imagen, bggId) {
  const value = canonicalizeImage(imagen, bggId)
  if (!value) return ''
  if (/^https?:\/\//i.test(value)) {
    return isBggCdn(value) ? '' : value
  }
  return BACKEND_URL + (value.startsWith('/') ? value : `/${value}`)
}
