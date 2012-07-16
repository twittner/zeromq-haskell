#include <zmq.h>

#ifndef ZMQ_HAVE_WINDOWS

#include <signal.h>
#include <assert.h>

void* init (int nthreads) {
        signal (SIGVTALRM, SIG_IGN);
        return zmq_init (nthreads);
}

#else

void* init (int nthreads) {
        return zmq_init (nthreads);
}

#endif
