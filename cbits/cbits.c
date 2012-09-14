#include <zmq.h>

#ifndef ZMQ_HAVE_WINDOWS

#include <signal.h>

typedef void (*sighandler_t)(int);

int term (void* ctx) {
        int i, ret;
        /* signals NOT to mask during termination */
        const int signal_retain[] = { SIGQUIT, SIGILL, SIGFPE, SIGSEGV, SIGTERM };
        const int num_retained = sizeof signal_retain / sizeof signal_retain[0];
        /* signals to mask during termination */
        int signal_mask[NSIG];
        int num_masked = 0;
        /* signal handlers to restore after termination */
        sighandler_t saved_handlers[NSIG];

        /* build an array of signals to mask */
        for (i = 1; i < NSIG; ++i) {
                int j;
                for (j = 0; j < num_retained; ++j)
                        if (i == signal_retain[j]) break;
                if (j == num_retained)
                        signal_mask[num_masked++] = i;
        }

        /* disable all but the specified signals */
        for (i = 0; i < num_masked; ++i)
                saved_handlers[i] = signal (signal_mask[i], SIG_IGN);

        ret = zmq_term (ctx);

        /* restore all previously disabled signal handlers */
        for (i = 0; i < num_masked; ++i)
                if (saved_handlers[i] != SIG_ERR)
                        signal (signal_mask[i], saved_handlers[i]);

        return ret;
}

#else

int term (void* ctx) {
        return zmq_term (ctx);
}

#endif
