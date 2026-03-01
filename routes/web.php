<?php

use Illuminate\Http\Request;
use App\Contracts\ReportManager;
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\BrandController;
use App\Http\Controllers\CategoryController;
use App\Http\Controllers\DashboardController;
use App\Http\Controllers\SettingsController;
use App\Http\Controllers\TransactionController;
use App\Http\Controllers\Auth\AuthenticatedSessionController;
use App\Http\Controllers\Api\V1\MetricsController;
use App\Http\Controllers\Api\V1\Admin\AuditLogController;
use App\Http\Controllers\Api\V1\Admin\SystemHealthController;

Route::redirect('/', '/dashboard');

Route::middleware(['auth'])->group(function () {
    Route::get('/dashboard', [DashboardController::class, 'index'])->name('dashboard');

    Route::get('/transactions', [TransactionController::class, 'index'])->name('transactions');
    Route::get('/brands', [BrandController::class, 'index'])->name('brands');
    Route::get('/categories', [CategoryController::class, 'index'])->name('categories');
    Route::get('/settings', [SettingsController::class, 'index'])->name('settings');
    Route::get('/admin', function () {
        return inertia('Admin/Dashboard');
    })->name('admin.dashboard')->middleware('admin');
    Route::get('/report', function (Request $request) {
        $start_date = $request->query('start_date');
        $end_date = $request->query('end_date');

        $data = [
            'sections' => app(ReportManager::class)->generate($start_date, $end_date),
            'currency' => config('hisabi.currency'),
            'range' => $start_date && $end_date ? $start_date . ' - ' . $end_date : now()->format('F Y')
        ];

        return view('report', $data);
    });

    Route::prefix('api/v1')->group(function () {
        Route::apiResource('transactions', \App\Http\Controllers\Api\V1\TransactionController::class)
            ->except(['show']);
        Route::get('/brands', [\App\Http\Controllers\Api\V1\BrandController::class, 'index']);
        Route::get('/brands/all', [\App\Http\Controllers\Api\V1\BrandController::class, 'all']);
        Route::post('/brands', [\App\Http\Controllers\Api\V1\BrandController::class, 'store']);
        Route::put('/brands/{id}', [\App\Http\Controllers\Api\V1\BrandController::class, 'update']);
        Route::delete('/brands/{id}', [\App\Http\Controllers\Api\V1\BrandController::class, 'destroy']);
        Route::get('/sms', [\App\Http\Controllers\Api\V1\SmsController::class, 'index']);
        Route::post('/sms', [\App\Http\Controllers\Api\V1\SmsController::class, 'store']);
        Route::put('/sms/{id}', [\App\Http\Controllers\Api\V1\SmsController::class, 'update']);
        Route::delete('/sms/{id}', [\App\Http\Controllers\Api\V1\SmsController::class, 'destroy']);
        Route::get('/categories/all', [\App\Http\Controllers\Api\V1\CategoryController::class, 'all']);
        Route::get('/tags', [\App\Http\Controllers\Api\V1\TagController::class, 'index']);
        Route::get('/tags/all', [\App\Http\Controllers\Api\V1\TagController::class, 'all']);
        Route::post('/tags', [\App\Http\Controllers\Api\V1\TagController::class, 'store']);
        Route::put('/tags/{uuid}', [\App\Http\Controllers\Api\V1\TagController::class, 'update']);
        Route::delete('/tags/{uuid}', [\App\Http\Controllers\Api\V1\TagController::class, 'destroy']);
        Route::get('/tags/{uuid}/transactions', [\App\Http\Controllers\Api\V1\TagController::class, 'transactions']);
        Route::post('/categories', [\App\Http\Controllers\Api\V1\CategoryController::class, 'store']);
        Route::put('/categories/{id}', [\App\Http\Controllers\Api\V1\CategoryController::class, 'update']);
        Route::delete('/categories/{id}', [\App\Http\Controllers\Api\V1\CategoryController::class, 'destroy']);
        Route::get('/budgets', [\App\Http\Controllers\Api\V1\BudgetController::class, 'index']);
        Route::post('/ai/chat', [\App\Http\Controllers\Api\V1\AIController::class, 'chat']);
        Route::put('/user/profile', [\App\Http\Controllers\Api\V1\UserController::class, 'updateProfile']);

        Route::post('/import/csv', [\App\Http\Controllers\Api\V1\ImportController::class, 'importCsv']);
        Route::post('/import/excel', [\App\Http\Controllers\Api\V1\ImportController::class, 'importExcel']);
        Route::get('/import/template', [\App\Http\Controllers\Api\V1\ImportController::class, 'downloadTemplate']);

        // User Preferences
        Route::get('/user/preferences', [\App\Http\Controllers\Api\V1\SettingsController::class, 'getPreferences']);
        Route::put('/user/preferences', [\App\Http\Controllers\Api\V1\SettingsController::class, 'updatePreferences']);

        // API Keys
        Route::get('/api-keys', [\App\Http\Controllers\Api\V1\ApiKeyController::class, 'index']);
        Route::post('/api-keys', [\App\Http\Controllers\Api\V1\ApiKeyController::class, 'store']);
        Route::delete('/api-keys/{uuid}', [\App\Http\Controllers\Api\V1\ApiKeyController::class, 'destroy']);

        // SMS Parser Rules
        Route::get('/sms-parser-rules', [\App\Http\Controllers\Api\V1\SmsParserController::class, 'index']);
        Route::post('/sms-parser-rules', [\App\Http\Controllers\Api\V1\SmsParserController::class, 'store']);
        Route::put('/sms-parser-rules/{uuid}', [\App\Http\Controllers\Api\V1\SmsParserController::class, 'update']);
        Route::delete('/sms-parser-rules/{uuid}', [\App\Http\Controllers\Api\V1\SmsParserController::class, 'destroy']);
        Route::post('/sms-parser-rules/test', [\App\Http\Controllers\Api\V1\SmsParserController::class, 'test']);

        Route::prefix('metrics')->group(function () {
            Route::get('/total-income', [MetricsController::class, 'totalIncome']);
            Route::get('/total-expenses', [MetricsController::class, 'totalExpenses']);
            Route::get('/total-savings', [MetricsController::class, 'totalSavings']);
            Route::get('/total-investment', [MetricsController::class, 'totalInvestment']);
            Route::get('/total-cash', [MetricsController::class, 'totalCash']);
            Route::get('/net-worth', [MetricsController::class, 'netWorth']);
            Route::get('/net-worth-trend', [MetricsController::class, 'netWorthTrend']);
            Route::get('/total-income-trend', [MetricsController::class, 'totalIncomeTrend']);
            Route::get('/total-expenses-trend', [MetricsController::class, 'totalExpensesTrend']);
            Route::get('/category-trend', [MetricsController::class, 'categoryTrend']);
            Route::get('/category-daily-trend', [MetricsController::class, 'categoryDailyTrend']);
            Route::get('/brand-trend', [MetricsController::class, 'brandTrend']);
            Route::get('/brand-change-rate', [MetricsController::class, 'brandChangeRate']);
            Route::get('/expenses-by-category', [MetricsController::class, 'expensesByCategory']);
            Route::get('/income-by-category', [MetricsController::class, 'incomeByCategory']);
            Route::get('/spending-by-brand', [MetricsController::class, 'spendingByBrand']);
            Route::get('/transactions-count', [MetricsController::class, 'transactionsCount']);
            Route::get('/transactions-by-category', [MetricsController::class, 'transactionsByCategory']);
            Route::get('/transactions-by-brand', [MetricsController::class, 'transactionsByBrand']);
            Route::get('/highest-transaction', [MetricsController::class, 'highestTransaction']);
            Route::get('/lowest-transaction', [MetricsController::class, 'lowestTransaction']);
            Route::get('/average-transaction', [MetricsController::class, 'averageTransaction']);
            Route::get('/transactions-std-dev', [MetricsController::class, 'transactionsStdDev']);
            Route::get('/brand-stats', [MetricsController::class, 'brandStats']);
            Route::get('/category-stats', [MetricsController::class, 'categoryStats']);
            Route::get('/circle-pack', [MetricsController::class, 'circlePack']);
            Route::get('/cash-flow', [MetricsController::class, 'cashFlow']);
            Route::get('/savings-rate', [MetricsController::class, 'savingsRate']);
            Route::get('/emergency-fund-status', [MetricsController::class, 'emergencyFundStatus']);
            Route::get('/financial-health-score', [MetricsController::class, 'financialHealthScore']);
            Route::get('/spending-alerts', [MetricsController::class, 'spendingAlerts']);
            Route::get('/top-expenses', [MetricsController::class, 'topExpenses']);
            Route::get('/recurring-expenses', [MetricsController::class, 'recurringExpenses']);
            Route::get('/cash-runway', [MetricsController::class, 'cashRunway']);
            Route::get('/income-stability', [MetricsController::class, 'incomeStability']);
            Route::get('/budget-allocation', [MetricsController::class, 'budgetAllocation']);
            Route::get('/financial-projection', [MetricsController::class, 'financialProjection']);
        });

        // Admin routes
        Route::prefix('admin')->middleware(['admin'])->group(function () {
            Route::get('/audit-logs', [AuditLogController::class, 'index']);
            Route::get('/audit-logs/{id}', [AuditLogController::class, 'show']);
            Route::get('/audit-logs/actions', [AuditLogController::class, 'actions']);
            Route::get('/audit-logs/entity-types', [AuditLogController::class, 'entityTypes']);
            Route::get('/system-health', [SystemHealthController::class, 'index']);
        });
    });

    Route::post('/logout', [AuthenticatedSessionController::class, 'destroy'])->name('logout');
});

Route::middleware(['guest'])->group(function () {
    Route::get('/login', [AuthenticatedSessionController::class, 'create'])->name('login');

    Route::post('/login', [AuthenticatedSessionController::class, 'store']);
});