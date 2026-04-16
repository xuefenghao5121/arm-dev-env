#include <stdio.h>
#include <time.h>

// ARM ISA feature detection test
// Prints architecture, compiler, and available ISA extensions

#define ITERATIONS 100000000

int main() {
    printf("ARM Dev Environment - ISA Feature Report\n");
    printf("=========================================\n");

    // Architecture
#if defined(__aarch64__)
    printf("Architecture: aarch64 (ARM 64-bit)\n");
#elif defined(__arm__)
    printf("Architecture: arm (ARM 32-bit)\n");
#elif defined(__x86_64__)
    printf("Architecture: x86_64 (native x86)\n");
#else
    printf("Architecture: unknown\n");
#endif

    // Compiler
    printf("Compiler: %s\n",
#if defined(__GNUC__)
           "GCC"
#elif defined(__clang__)
           "Clang"
#else
           "Unknown"
#endif
    );

    // ARM ISA version
#if defined(__ARM_ARCH)
    printf("ARM_ARCH: %d\n", __ARM_ARCH);
#endif

    // ISA features
    printf("\n--- ISA Features ---\n");
#if defined(__ARM_FEATURE_SVE)
    printf("SVE:     yes (vector bits: %d)\n", __ARM_FEATURE_SVE_BITS);
#else
    printf("SVE:     no\n");
#endif

#if defined(__ARM_FEATURE_SVE2)
    printf("SVE2:    yes\n");
#else
    printf("SVE2:    no\n");
#endif

#if defined(__ARM_FEATURE_LSE)
    printf("LSE:     yes (atomic instructions)\n");
#else
    printf("LSE:     no\n");
#endif

#if defined(__ARM_FEATURE_CRYPTO)
    printf("Crypto:  yes (AES + SHA)\n");
#else
    printf("Crypto:  no\n");
#endif

#if defined(__ARM_FEATURE_RCPC)
    printf("RCPC:    yes (LDAPR)\n");
#else
    printf("RCPC:    no\n");
#endif

#if defined(__ARM_FEATURE_UNALIGNED)
    printf("Unaligned: yes\n");
#else
    printf("Unaligned: no\n");
#endif

    // Simple compute benchmark
    printf("\n--- Compute Benchmark ---\n");
    volatile double result = 0.0;
    clock_t start = clock();
    for (long i = 0; i < ITERATIONS; i++) {
        result += (double)i * 0.0001;
    }
    clock_t end = clock();

    double elapsed = (double)(end - start) / CLOCKS_PER_SEC;
    printf("Iterations: %ld\n", ITERATIONS);
    printf("Elapsed:    %.3f seconds\n", elapsed);
    printf("Result:     %f\n", (double)result);

    return 0;
}
