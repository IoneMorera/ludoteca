<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\MobileErrorLog;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

class ErrorLogController extends Controller
{
    /**
     * Recibe logs de error desde la app móvil y los almacena.
     */
    public function store(Request $request): JsonResponse
    {
        $request->validate([
            'app_version' => 'nullable|string|max:20',
            'device_model' => 'nullable|string|max:255',
            'os_version' => 'nullable|string|max:80',
            'connection_type' => 'nullable|string|max:40',
            'free_memory' => 'nullable|string|max:40',
            'logs' => 'required|array|min:1|max:50',
            'logs.*.timestamp' => 'required|string',
            'logs.*.level' => 'nullable|string|max:20',
            'logs.*.context' => 'required|string|max:255',
            'logs.*.message' => 'required|string|max:5000',
            'logs.*.stack_trace' => 'nullable|string|max:10000',
            'logs.*.extra' => 'nullable|array',
            'logs.*.device_model' => 'nullable|string|max:255',
            'logs.*.os_version' => 'nullable|string|max:80',
            'logs.*.connection_type' => 'nullable|string|max:40',
            'logs.*.free_memory' => 'nullable|string|max:40',
        ]);

        $user = $request->user();
        $appVersion = $request->input('app_version');
        $userName = $request->input('user_name') ?? $user?->name;

        $logs = $request->input('logs', []);
        $inserted = 0;

        foreach ($logs as $log) {
            $extra = $log['extra'] ?? [];
            if (!is_array($extra)) {
                $extra = [];
            }

            try {
                MobileErrorLog::create([
                    'user_id' => $user?->id,
                    'user_name' => $userName,
                    'app_version' => $appVersion,
                    'device_model' => $log['device_model']
                        ?? $extra['device_model']
                        ?? $request->input('device_model'),
                    'os_version' => $log['os_version']
                        ?? $extra['os_version']
                        ?? $request->input('os_version'),
                    'connection_type' => $log['connection_type']
                        ?? $extra['connection_type']
                        ?? $request->input('connection_type'),
                    'free_memory' => $log['free_memory']
                        ?? $extra['free_memory']
                        ?? $request->input('free_memory'),
                    'level' => $log['level'] ?? 'error',
                    'context' => $log['context'],
                    'message' => mb_substr($log['message'], 0, 5000),
                    'stack_trace' => isset($log['stack_trace'])
                        ? mb_substr($log['stack_trace'], 0, 10000)
                        : null,
                    'extra' => $extra ?: null,
                    'reported_at' => $log['timestamp'],
                ]);
                $inserted++;
            } catch (\Throwable $e) {
                Log::warning('ErrorLogController: failed to store log', [
                    'error' => $e->getMessage(),
                    'log_context' => $log['context'] ?? '?',
                ]);
            }
        }

        return response()->json([
            'stored' => $inserted,
            'received' => count($logs),
        ]);
    }
}
