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
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\Rules\Password;

class AuthController extends Controller
{
    public function register(Request $request): JsonResponse
    {
        Log::debug('register: validating input', ['email' => $request->input('email')]);

        $validated = $request->validate([
            'name' => 'required|string|max:255',
            'email' => 'required|string|email|max:255|unique:central.users,email',
            'password' => ['required', 'confirmed', Password::min(8)],
            'bgg_username' => 'nullable|string|max:255',
        ]);

        Log::debug('register: validation passed, creating tenant');

        try {
            $tenant = Tenant::create();
            Log::debug('register: tenant created', ['tenant_id' => $tenant->id]);
        } catch (\Throwable $e) {
            Log::error('register: failed to create tenant', [
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);
            throw $e;
        }

        try {
            $user = User::create([
                'name' => $validated['name'],
                'email' => $validated['email'],
                'password' => Hash::make($validated['password']),
                'tenant_id' => $tenant->id,
                'bgg_username' => $validated['bgg_username'] ?? null,
            ]);
            Log::debug('register: user created', ['user_id' => $user->id]);
        } catch (\Throwable $e) {
            Log::error('register: failed to create user', [
                'tenant_id' => $tenant->id,
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);
            throw $e;
        }

        try {
            $tenant->run(function () use ($validated) {
                Log::debug('register: creating Propietario inside tenant context');
                Propietario::create([
                    'nombre' => $validated['name'],
                    'bgg_username' => $validated['bgg_username'] ?? null,
                    'es_principal' => true,
                ]);
                Log::debug('register: Propietario created');
            });
        } catch (\Throwable $e) {
            Log::error('register: failed to create Propietario in tenant context', [
                'tenant_id' => $tenant->id,
                'user_id' => $user->id,
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);
            throw $e;
        }

        try {
            $token = $user->createToken('web')->plainTextToken;
            Log::debug('register: token created', ['user_id' => $user->id]);
        } catch (\Throwable $e) {
            Log::error('register: failed to create token after registration', [
                'user_id' => $user->id,
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);
            throw $e;
        }

        return response()->json([
            'user' => $user->toApiArray(),
            'token' => $token,
        ], 201);
    }

    public function login(Request $request): JsonResponse
    {
        $credentials = $request->validate([
            'email' => 'required|email',
            'password' => 'required',
        ]);

        if (!Auth::attempt($credentials)) {
            return response()->json([
                'message' => 'Credenciales incorrectas.',
            ], 422);
        }

        /** @var \App\Models\User $user */
        $user = Auth::user();
        $token = $user->createToken('web')->plainTextToken;

        return response()->json([
            'user' => $user->toApiArray(),
            'token' => $token,
        ]);
    }

    public function logout(Request $request): JsonResponse
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json(null, 204);
    }

    public function user(Request $request): JsonResponse
    {
        return response()->json([
            'user' => $request->user()->toApiArray(),
        ]);
    }

    public function updateUser(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'name' => 'sometimes|required|string|max:255',
            'bgg_username' => 'sometimes|nullable|string|max:255',
            'no_enfundo' => 'sometimes|boolean',
            'ocultar_por_estrenar' => 'sometimes|boolean',
            'ocultar_faltan_traduccion' => 'sometimes|boolean',
            'ocultar_expansion_otro_idioma' => 'sometimes|boolean',
            'ocultar_por_colocar' => 'sometimes|boolean',
            'ocultar_nuevas_expansiones' => 'sometimes|boolean',
        ]);

        /** @var \App\Models\User $user */
        $user = $request->user();
        $user->fill($validated);
        $user->save();

        return response()->json([
            'user' => $user->toApiArray(),
        ]);
    }

    public function mobileLogin(Request $request): JsonResponse
    {
        $credentials = $request->validate([
            'email' => 'required|email',
            'password' => 'required',
        ]);

        if (!Auth::attempt($credentials)) {
            return response()->json([
                'message' => 'Credenciales incorrectas.',
            ], 422);
        }

        /** @var \App\Models\User $user */
        $user = Auth::user();
        $token = $user->createToken('mobile')->plainTextToken;

        return response()->json([
            'user' => $user->toApiArray(),
            'token' => $token,
        ]);
    }

    public function mobileLogout(Request $request): JsonResponse
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json(null, 204);
    }
}
