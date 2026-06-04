#ifndef GREET_H
#define GREET_H

/* Returns a greeting. Lives in libgreet.so, not in the executable — so the
   package is only runnable if the shared library is bundled and found. */
const char *greet_message(void);

#endif
