<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Stancl\Tenancy\Tenancy;

class InitializeTenancyByUser
{
    public function __construct(protected Tenancy $tenancy)
    {
    }

    public function handle(Request $request, Closure $next)
    {
        $user = $request->user();

        if (!$user || !$user->tenant_id) {
            return response()->json(['message' => 'Tenant no encontrado.'], 403);
        }

        $this->tenancy->initialize(
            \App\Models\Tenant::find($user->tenant_id)
        );

        return $next($request);
    }
}
