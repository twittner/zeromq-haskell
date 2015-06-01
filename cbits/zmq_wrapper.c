#include <pthread.h>
#include <signal.h>
#include <stdbool.h>
#include <zmq_wrapper.h>

static sigset_t signals[1];
static bool signals_initialised;

static void init_rts_sigset() {
    static pthread_mutex_t sigs_mutex = PTHREAD_MUTEX_INITIALIZER;
    pthread_mutex_lock(&sigs_mutex);
    if (!signals_initialised) {
	sigemptyset(signals);
	sigaddset(signals, SIGALRM);
	sigaddset(signals, SIGVTALRM);
	signals_initialised = true;
    }
    pthread_mutex_unlock(&sigs_mutex);
}

#define rts_signals_block() \
    do { \
        if (!signals_initialised) init_rts_sigset(); \
        pthread_sigmask(SIG_BLOCK, signals, NULL);	\
    } while (0)

#define rts_signals_unblock() pthread_sigmask(SIG_UNBLOCK, signals, NULL)

int hs_zmq_bind (void *s, const char *addr) {
        int x;
        rts_signals_block();
        x = zmq_bind(s, addr);
        rts_signals_unblock();
        return x;
}

int hs_zmq_connect (void *s, const char *addr) {
        int x;
        rts_signals_block();
        x = zmq_connect(s, addr);
        rts_signals_unblock();
        return x;
}

int hs_zmq_unbind (void *s, const char *addr) {
        int x;
        rts_signals_block();
        x = zmq_unbind(s, addr);
        rts_signals_unblock();
        return x;
}

int hs_zmq_disconnect (void *s, const char *addr) {
        int x;
        rts_signals_block();
        x = zmq_disconnect(s, addr);
        rts_signals_unblock();
        return x;
}

int hs_zmq_getsockopt (void *s, int option, void *optval, size_t *optvallen) {
        int x;
        rts_signals_block();
        x = zmq_getsockopt(s, option, optval, optvallen);
        rts_signals_unblock();
        return x;
}

int hs_zmq_setsockopt (void *s, int option, const void *optval, size_t optvallen) {
        int x;
        rts_signals_block();
        x = zmq_setsockopt(s, option, optval, optvallen);
        rts_signals_unblock();
        return x;
}

int hs_zmq_sendmsg (void *s, zmq_msg_t *msg, int flags) {
        int x;
        rts_signals_block();
        x = zmq_sendmsg(s, msg, flags);
        rts_signals_unblock();
        return x;
}

int hs_zmq_recvmsg (void *s, zmq_msg_t *msg, int flags) {
        int x;
        rts_signals_block();
        x = zmq_recvmsg(s, msg, flags);
        rts_signals_unblock();
        return x;
}

int hs_zmq_poll (zmq_pollitem_t *items, int nitems, long timeout) {
        int x;
        rts_signals_block();
        x = zmq_poll(items, nitems, timeout);
        rts_signals_unblock();
        return x;
}

int hs_zmq_proxy (void *frontend, void *backend, void *capture) {
        int x;
        rts_signals_block();
        x = zmq_proxy(frontend, backend, capture);
        rts_signals_unblock();
        return x;
}

int hs_zmq_socket_monitor (void *s, const char *addr, int events) {
        int x;
        rts_signals_block();
        x = zmq_socket_monitor(s, addr, events);
        rts_signals_unblock();
        return x;
}
