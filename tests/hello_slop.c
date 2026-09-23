#include <stdio.h>

void unused_function() {
  
  printf("see ya %i!\n", UNDEFINED_MACRO(4));
}

int main(void)
{
    // Print "hello world" to STDOUT - for easy redirection to /dev/null
    printf("hello, world\n");

    // Returning 0 - No Error
    return 0;
}
