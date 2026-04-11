--experimental:views
--hints:off

task test, "Run tests":
  exec "nimble test"

task testMetrics, "Run performance metrics manually":
  exec "nim c -d:debugMetrics -r tests/perf_metrics.nim"

task benchmark, "Run performance benchmark":
  exec "nim c -d:debugMetrics -d:release -r metrics_benchmark.nim"
