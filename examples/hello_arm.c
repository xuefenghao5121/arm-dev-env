#include <stdio.h>
#include <time.h>

// Simple compute workload to verify ARM compilation and execution

#define ITERATIONS 100000000

int main() {
    printf("ARM Dev Environment - Compute Test\n");
    printf("===================================\n");

#if defined(__aarch64__)
    printf("Architecture: aarch64 (ARM 64-bit)\n");
#elif defined(__arm__)
    printf("Architecture: arm (ARM 32-bit)\n");
#elif defined(__x86_64__)
    printf("Architecture: x86_64 (native x86)\n");
#else
    printf("Architecture: unknown\n");
#endif

    printf("Compiler: %s\n",
#if defined(__GNUC__)
           "GCC"
#elif defined(__clang__)
           "Clang"
#else
           "Unknown"
#endif
    );

    // Simple compute benchmark
    volatile double result = 0.0;
    clock_t start = clock();
    for (long i = 0; i < ITERATIONS; i++) {
        result += (double)i * 0.0001;
    }
    clock_t end = clock();

    double elapsed = (double)(end - start) / CLOCKS_PER_SEC;
    printf("Compute test: %.3f seconds (%ld iterations)\n", elapsed, ITERATIONS);
    printf("Result: %f\n", (double)result);

    return 0;
}
