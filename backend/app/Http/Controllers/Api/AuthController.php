<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Propietario;
use App\Models\Tenant;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rules\Password;

class AuthController extends Controller
{
    public function register(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'name' => 'required|string|max:255',
            'email' => 'required|string|email|max:255|unique:central.users,email',
            'password' => ['required', 'confirmed', Password::min(8)],
            'bgg_username' => 'nullable|string|max:255',
        ]);

        $tenant = Tenant::create();

        $user = User::create([
            'name' => $validated['name'],
            'email' => $validated['email'],
            'password' => Hash::make($validated['password']),
            'tenant_id' => $tenant->id,
            'bgg_username' => $validated['bgg_username'] ?? null,
        ]);

        $tenant->run(function () use ($validated) {
            Propietario::create([
                'nombre' => $validated['name'],
            ]);
        });

        Auth::login($user);

        return response()->json([
            'user' => $user->only('id', 'name', 'email', 'bgg_username'),
        ], 201);
    }

    public function login(Request $request): JsonResponse
    {
        $credentials = $request->validate([
            'email' => 'required|email',
            'password' => 'required',
        ]);

        if (!Auth::attempt($credentials, $request->boolean('remember'))) {
            return response()->json([
                'message' => 'Credenciales incorrectas.',
            ], 422);
        }

        $request->session()->regenerate();

        /** @var \App\Models\User $user */
        $user = Auth::user();

        return response()->json([
            'user' => $user->only('id', 'name', 'email', 'bgg_username'),
        ]);
    }

    public function logout(Request $request): JsonResponse
    {
        Auth::guard('web')->logout();
        $request->session()->invalidate();
        $request->session()->regenerateToken();

        return response()->json(null, 204);
    }

    public function user(Request $request): JsonResponse
    {
        return response()->json([
            'user' => $request->user()->only('id', 'name', 'email', 'bgg_username'),
        ]);
    }
}
