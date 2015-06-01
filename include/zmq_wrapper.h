#ifndef __ZMQ_WRAPPER_H__
#define __ZMQ_WRAPPER_H__

#include <zmq.h>


int hs_zmq_bind (void *s, const char *addr);
int hs_zmq_connect (void *s, const char *addr);
int hs_zmq_unbind (void *s, const char *addr);
int hs_zmq_disconnect (void *s, const char *addr);
int hs_zmq_getsockopt (void *s, int option, void *optval, size_t *optvallen);
int hs_zmq_setsockopt (void *s, int option, const void *optval, size_t optvallen);
int hs_zmq_sendmsg (void *s, zmq_msg_t *msg, int flags);
int hs_zmq_recvmsg (void *s, zmq_msg_t *msg, int flags);
int hs_zmq_poll (zmq_pollitem_t *items, int nitems, long timeout);
int hs_zmq_proxy (void *frontend, void *backend, void *capture);
int hs_zmq_socket_monitor (void *s, const char *addr, int events);

#endif // __ZMQ_WRAPPER_H__
