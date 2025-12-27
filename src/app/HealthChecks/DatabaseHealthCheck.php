<?php

namespace App\HealthChecks;

use Illuminate\Support\Facades\DB;
use Spatie\Health\Checks\Check;
use Spatie\Health\Checks\Result;

class DatabaseHealthCheck extends Check
{
    public function run(): Result
    {
        try {
            DB::connection()->getPdo();

            return Result::make()->ok();
        } catch (\Exception $e) {
            return Result::make()
                ->failed('Database connection failed: ' . $e->getMessage());
        }
    }
}
