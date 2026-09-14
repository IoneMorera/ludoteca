<?php

namespace App\Support;

class GameImageUrl
{
    /**
     * Convierte portadas del CDN de BGG a la ruta pública de Laravel.
     * Evita que clientes en España pidan cf.geekdo-images.com (IPs de
     * Cloudflare bloqueadas por operadores durante partidos de LaLiga).
     */
    public static function isBggCdn(?string $url): bool
    {
        if ($url === null || $url === '') {
            return false;
        }

        return (bool) preg_match(
            '#(?:^https?:)?//(?:[^/]*\.)?(?:geekdo-images\.com|geekdo\.com)/#i',
            $url
        );
    }

    public static function storagePath(int $bggId, ?string $sourceUrl = null): string
    {
        return '/storage/juegos/bgg_' . $bggId . '.' . self::extensionOf($sourceUrl);
    }

    public static function extensionOf(?string $sourceUrl): string
    {
        if (!$sourceUrl) {
            return 'jpg';
        }

        $path = parse_url($sourceUrl, PHP_URL_PATH) ?: $sourceUrl;
        $ext = strtolower((string) pathinfo($path, PATHINFO_EXTENSION));
        $allowed = ['jpg', 'jpeg', 'png', 'webp', 'gif'];
        if (!in_array($ext, $allowed, true)) {
            return 'jpg';
        }

        return $ext === 'jpeg' ? 'jpg' : $ext;
    }

    public static function canonicalize(?string $imagen, ?int $bggId): ?string
    {
        if ($imagen === null || $imagen === '') {
            return $imagen;
        }

        if (!self::isBggCdn($imagen)) {
            return $imagen;
        }

        if ($bggId === null) {
            return null;
        }

        return self::storagePath($bggId, $imagen);
    }
}
