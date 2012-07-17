#include <zmq.h>

#ifndef ZMQ_HAVE_WINDOWS

#include <signal.h>

int term (void* ctx) {
        signal (SIGVTALRM, SIG_IGN);
        return zmq_term (ctx);
}

#else

int term (void* ctx) {
        return zmq_term (ctx);
}

#endif
