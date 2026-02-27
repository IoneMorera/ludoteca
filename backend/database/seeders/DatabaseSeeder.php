<?php

namespace Database\Seeders;

use App\Models\Categoria;
use App\Models\Juego;
use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        $categorias = [
            ['nombre' => 'Juegos de mesa', 'descripcion' => 'Juegos de tablero clásicos y modernos'],
            ['nombre' => 'Juegos de cartas', 'descripcion' => 'Juegos basados en cartas'],
            ['nombre' => 'Juegos de estrategia', 'descripcion' => 'Juegos que requieren planificación y táctica'],
            ['nombre' => 'Juegos cooperativos', 'descripcion' => 'Juegos donde todos los jugadores colaboran'],
            ['nombre' => 'Juegos infantiles', 'descripcion' => 'Juegos diseñados para los más pequeños'],
            ['nombre' => 'Juegos de rol', 'descripcion' => 'Juegos de interpretación de personajes'],
            ['nombre' => 'Puzzles', 'descripcion' => 'Rompecabezas y puzzles de diversas piezas'],
            ['nombre' => 'Importado BGG', 'descripcion' => 'Juegos importados desde BoardGameGeek'],
        ];

        foreach ($categorias as $cat) {
            Categoria::firstOrCreate(['nombre' => $cat['nombre']], $cat);
        }

        $juegos = [
            ['nombre' => 'Catan', 'descripcion' => 'Juego de colonización y comercio', 'edad_minima' => 10, 'num_jugadores_min' => 3, 'num_jugadores_max' => 4, 'categoria_id' => 3],
            ['nombre' => 'Dobble', 'descripcion' => 'Juego de rapidez visual con cartas', 'edad_minima' => 6, 'num_jugadores_min' => 2, 'num_jugadores_max' => 8, 'categoria_id' => 2],
            ['nombre' => 'Pandemic', 'descripcion' => 'Juego cooperativo para salvar al mundo', 'edad_minima' => 8, 'num_jugadores_min' => 2, 'num_jugadores_max' => 4, 'categoria_id' => 4],
            ['nombre' => 'Monopoly', 'descripcion' => 'El clásico juego de compraventa', 'edad_minima' => 8, 'num_jugadores_min' => 2, 'num_jugadores_max' => 6, 'categoria_id' => 1],
            ['nombre' => 'UNO', 'descripcion' => 'Juego de cartas para toda la familia', 'edad_minima' => 7, 'num_jugadores_min' => 2, 'num_jugadores_max' => 10, 'categoria_id' => 2],
        ];

        foreach ($juegos as $juego) {
            Juego::firstOrCreate(['nombre' => $juego['nombre']], $juego);
        }
    }
}
