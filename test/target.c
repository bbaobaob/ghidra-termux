/* Tiny multi-function ARM64 test target for ghidra-termux smoke tests.
 * Build:  gcc -O1 -o test-target target.c
 * Exercises: loops, string compares, switch dispatch, printf calls.
 */
#include <stdio.h>
#include <string.h>

int add(int a, int b)
{
    return a + b;
}

unsigned long factorial(unsigned int n)
{
    unsigned long r = 1;
    for (unsigned int i = 2; i <= n; i++)
        r *= i;
    return r;
}

void greet(const char *name)
{
    printf("Hello, %s!\n", name);
}

int check(const char *s)
{
    if (strcmp(s, "open") == 0)  return 1;
    if (strcmp(s, "close") == 0) return 2;
    return 0;
}

int classify(int x)
{
    switch (x % 4) {
    case 0: return 100;
    case 1: return 200;
    case 2: return 300;
    default: return 900;
    }
}

int main(int argc, char **argv)
{
    greet(argc > 1 ? argv[1] : "world");
    printf("add(2,3)=%d\n", add(2, 3));
    printf("factorial(10)=%lu\n", factorial(10));
    printf("classify(7)=%d\n", classify(7));
    return check(argc > 2 ? argv[2] : "");
}
