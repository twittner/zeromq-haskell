{-# LANGUAGE CPP                      #-}
{-# LANGUAGE ForeignFunctionInterface #-}

module System.ZMQ4.Base where

import Foreign
import Foreign.C.Types
import Foreign.C.String
import Control.Applicative

#include <zmq.h>

#if ZMQ_VERSION_MAJOR != 4
    #error *** INVALID 0MQ VERSION (must be 4.x) ***
#endif

-----------------------------------------------------------------------------
-- Message

newtype ZMQMsg = ZMQMsg
  { content :: Ptr ()
  } deriving (Eq, Ord)

instance Storable ZMQMsg where
    alignment _        = #{alignment zmq_msg_t}
    sizeOf    _        = #{size zmq_msg_t}
    peek p             = ZMQMsg <$> #{peek zmq_msg_t, _} p
    poke p (ZMQMsg c)  = #{poke zmq_msg_t, _} p c

-----------------------------------------------------------------------------
-- Poll

data ZMQPoll = ZMQPoll
    { pSocket  :: {-# UNPACK #-} !ZMQSocket
    , pFd      :: {-# UNPACK #-} !CInt
    , pEvents  :: {-# UNPACK #-} !CShort
    , pRevents :: {-# UNPACK #-} !CShort
    }

instance Storable ZMQPoll where
    alignment _ = #{alignment zmq_pollitem_t}
    sizeOf    _ = #{size zmq_pollitem_t}
    peek p = do
        s  <- #{peek zmq_pollitem_t, socket} p
        f  <- #{peek zmq_pollitem_t, fd} p
        e  <- #{peek zmq_pollitem_t, events} p
        re <- #{peek zmq_pollitem_t, revents} p
        return $ ZMQPoll s f e re
    poke p (ZMQPoll s f e re) = do
        #{poke zmq_pollitem_t, socket} p s
        #{poke zmq_pollitem_t, fd} p f
        #{poke zmq_pollitem_t, events} p e
        #{poke zmq_pollitem_t, revents} p re

type ZMQMsgPtr  = Ptr ZMQMsg
type ZMQCtx     = Ptr ()
type ZMQSocket  = Ptr ()
type ZMQPollPtr = Ptr ZMQPoll

#let alignment t = "%lu", (unsigned long)offsetof(struct {char x__; t (y__); }, y__)

-----------------------------------------------------------------------------
-- Socket Types

newtype ZMQSocketType = ZMQSocketType
  { typeVal :: CInt
  } deriving (Eq, Ord)

#{enum ZMQSocketType, ZMQSocketType
  , pair     = ZMQ_PAIR
  , pub      = ZMQ_PUB
  , sub      = ZMQ_SUB
  , xpub     = ZMQ_XPUB
  , xsub     = ZMQ_XSUB
  , request  = ZMQ_REQ
  , response = ZMQ_REP
  , dealer   = ZMQ_DEALER
  , router   = ZMQ_ROUTER
  , pull     = ZMQ_PULL
  , push     = ZMQ_PUSH
  , stream   = ZMQ_STREAM
}

-----------------------------------------------------------------------------
-- Socket Options

newtype ZMQOption = ZMQOption
  { optVal :: CInt
  } deriving (Eq, Ord)

#{enum ZMQOption, ZMQOption
  , affinity             = ZMQ_AFFINITY
  , backlog              = ZMQ_BACKLOG
  , conflate             = ZMQ_CONFLATE
  , curve                = ZMQ_CURVE
  , curvePublicKey       = ZMQ_CURVE_PUBLICKEY
  , curveSecretKey       = ZMQ_CURVE_SECRETKEY
  , curveServer          = ZMQ_CURVE_SERVER
  , curveServerKey       = ZMQ_CURVE_SERVERKEY
  , delayAttachOnConnect = ZMQ_DELAY_ATTACH_ON_CONNECT
  , events               = ZMQ_EVENTS
  , filedesc             = ZMQ_FD
  , identity             = ZMQ_IDENTITY
  , immediate            = ZMQ_IMMEDIATE
  , ipv4Only             = ZMQ_IPV4ONLY
  , ipv6                 = ZMQ_IPV6
  , lastEndpoint         = ZMQ_LAST_ENDPOINT
  , linger               = ZMQ_LINGER
  , maxMessageSize       = ZMQ_MAXMSGSIZE
  , mcastHops            = ZMQ_MULTICAST_HOPS
  , mechanism            = ZMQ_MECHANISM
  , null                 = ZMQ_NULL
  , plain                = ZMQ_PLAIN
  , plainPassword        = ZMQ_PLAIN_PASSWORD
  , plainServer          = ZMQ_PLAIN_SERVER
  , plainUserName        = ZMQ_PLAIN_USERNAME
  , probeRouter          = ZMQ_PROBE_ROUTER
  , rate                 = ZMQ_RATE
  , receiveBuf           = ZMQ_RCVBUF
  , receiveHighWM        = ZMQ_RCVHWM
  , receiveMore          = ZMQ_RCVMORE
  , receiveTimeout       = ZMQ_RCVTIMEO
  , reconnectIVL         = ZMQ_RECONNECT_IVL
  , reconnectIVLMax      = ZMQ_RECONNECT_IVL_MAX
  , recoveryIVL          = ZMQ_RECOVERY_IVL
  , reqCorrelate         = ZMQ_REQ_CORRELATE
  , reqRelaxed           = ZMQ_REQ_RELAXED
  , routerMandatory      = ZMQ_ROUTER_MANDATORY
  , sendBuf              = ZMQ_SNDBUF
  , sendHighWM           = ZMQ_SNDHWM
  , sendTimeout          = ZMQ_SNDTIMEO
  , subscribe            = ZMQ_SUBSCRIBE
  , tcpAcceptFilter      = ZMQ_TCP_ACCEPT_FILTER
  , tcpKeepAlive         = ZMQ_TCP_KEEPALIVE
  , tcpKeepAliveCount    = ZMQ_TCP_KEEPALIVE_CNT
  , tcpKeepAliveIdle     = ZMQ_TCP_KEEPALIVE_IDLE
  , tcpKeepAliveInterval = ZMQ_TCP_KEEPALIVE_INTVL
  , unsubscribe          = ZMQ_UNSUBSCRIBE
  , xpubVerbose          = ZMQ_XPUB_VERBOSE
  , zapDomain            = ZMQ_ZAP_DOMAIN
}

-----------------------------------------------------------------------------
-- Context Options

newtype ZMQCtxOption = ZMQCtxOption
  { ctxOptVal :: CInt
  } deriving (Eq, Ord)

#{enum ZMQCtxOption, ZMQCtxOption
  , _ioThreads = ZMQ_IO_THREADS
  , _maxSockets = ZMQ_MAX_SOCKETS
}

-----------------------------------------------------------------------------
-- Event Type

newtype ZMQEventType = ZMQEventType
  { eventTypeVal :: Word16
  } deriving (Eq, Ord, Show)

#{enum ZMQEventType, ZMQEventType
  , connected      = ZMQ_EVENT_CONNECTED
  , connectDelayed = ZMQ_EVENT_CONNECT_DELAYED
  , connectRetried = ZMQ_EVENT_CONNECT_RETRIED
  , listening      = ZMQ_EVENT_LISTENING
  , bindFailed     = ZMQ_EVENT_BIND_FAILED
  , accepted       = ZMQ_EVENT_ACCEPTED
  , acceptFailed   = ZMQ_EVENT_ACCEPT_FAILED
  , closed         = ZMQ_EVENT_CLOSED
  , closeFailed    = ZMQ_EVENT_CLOSE_FAILED
  , disconnected   = ZMQ_EVENT_DISCONNECTED
  , allEvents      = ZMQ_EVENT_ALL
  , monitorStopped = ZMQ_EVENT_MONITOR_STOPPED
}

-----------------------------------------------------------------------------
-- Event

data ZMQEvent = ZMQEvent
  { zeEvent :: {-# UNPACK #-} !ZMQEventType
  , zeValue :: {-# UNPACK #-} !Int32
  }

instance Storable ZMQEvent where
    alignment _ = #{alignment zmq_event_t}
    sizeOf    _ = #{size zmq_event_t}
    peek e = ZMQEvent
        <$> (ZMQEventType <$> #{peek zmq_event_t, event} e)
        <*> #{peek zmq_event_t, value} e
    poke e (ZMQEvent (ZMQEventType a) b) = do
        #{poke zmq_event_t, event} e a
        #{poke zmq_event_t, value} e b

-----------------------------------------------------------------------------
-- Security Mechanism

newtype ZMQSecMechanism = ZMQSecMechanism
  { secMechanism :: Int
  } deriving (Eq, Ord, Show)

#{enum ZMQSecMechanism, ZMQSecMechanism
  , secNull  = ZMQ_NULL
  , secPlain = ZMQ_PLAIN
  , secCurve = ZMQ_CURVE
}

-----------------------------------------------------------------------------
-- Message Options

newtype ZMQMsgOption = ZMQMsgOption
  { msgOptVal :: CInt
  } deriving (Eq, Ord)

#{enum ZMQMsgOption, ZMQMsgOption
  , more = ZMQ_MORE
}

-----------------------------------------------------------------------------
-- Flags

newtype ZMQFlag = ZMQFlag
  { flagVal :: CInt
  } deriving (Eq, Ord)

#{enum ZMQFlag, ZMQFlag
  , dontWait = ZMQ_DONTWAIT
  , sndMore  = ZMQ_SNDMORE
}

-----------------------------------------------------------------------------
-- Poll Events

newtype ZMQPollEvent = ZMQPollEvent
  { pollVal :: CShort
  } deriving (Eq, Ord)

#{enum ZMQPollEvent, ZMQPollEvent,
    pollIn    = ZMQ_POLLIN,
    pollOut   = ZMQ_POLLOUT,
    pollerr   = ZMQ_POLLERR
}

-----------------------------------------------------------------------------
-- function declarations

-- general initialization

foreign import ccall unsafe "zmq.h zmq_version"
    c_zmq_version :: Ptr CInt -> Ptr CInt -> Ptr CInt -> IO ()

foreign import ccall unsafe "zmq.h zmq_ctx_new"
    c_zmq_ctx_new :: IO ZMQCtx

foreign import ccall unsafe "zmq.h zmq_ctx_shutdown"
    c_zmq_ctx_shutdown :: ZMQCtx -> IO CInt

foreign import ccall unsafe "zmq.h zmq_ctx_term"
    c_zmq_ctx_term :: ZMQCtx -> IO CInt

foreign import ccall unsafe "zmq.h zmq_ctx_get"
    c_zmq_ctx_get :: ZMQCtx -> CInt -> IO CInt

foreign import ccall unsafe "zmq.h zmq_ctx_set"
    c_zmq_ctx_set :: ZMQCtx -> CInt -> CInt -> IO CInt

-- zmq_msg_t related

foreign import ccall unsafe "zmq.h zmq_msg_init"
    c_zmq_msg_init :: ZMQMsgPtr -> IO CInt

foreign import ccall unsafe "zmq.h zmq_msg_init_size"
    c_zmq_msg_init_size :: ZMQMsgPtr -> CSize -> IO CInt

foreign import ccall unsafe "zmq.h zmq_msg_close"
    c_zmq_msg_close :: ZMQMsgPtr -> IO CInt

foreign import ccall unsafe "zmq.h zmq_msg_data"
    c_zmq_msg_data :: ZMQMsgPtr -> IO (Ptr a)

foreign import ccall unsafe "zmq.h zmq_msg_size"
    c_zmq_msg_size :: ZMQMsgPtr -> IO CSize

foreign import ccall unsafe "zmq.h zmq_msg_get"
    c_zmq_msg_get :: ZMQMsgPtr -> CInt -> IO CInt

foreign import ccall unsafe "zmq.h zmq_msg_set"
    c_zmq_msg_set :: ZMQMsgPtr -> CInt -> CInt -> IO CInt

-- socket

foreign import ccall unsafe "zmq.h zmq_socket"
    c_zmq_socket :: ZMQCtx -> CInt -> IO ZMQSocket

foreign import ccall unsafe "zmq.h zmq_close"
    c_zmq_close :: ZMQSocket -> IO CInt

foreign import ccall unsafe "zmq.h zmq_setsockopt"
    c_zmq_setsockopt :: ZMQSocket
                     -> CInt   -- option
                     -> Ptr () -- option value
                     -> CSize  -- option value size
                     -> IO CInt

foreign import ccall unsafe "zmq.h zmq_getsockopt"
    c_zmq_getsockopt :: ZMQSocket
                     -> CInt       -- option
                     -> Ptr ()     -- option value
                     -> Ptr CSize  -- option value size ptr
                     -> IO CInt

foreign import ccall unsafe "zmq.h zmq_bind"
    c_zmq_bind :: ZMQSocket -> CString -> IO CInt

foreign import ccall unsafe "zmq.h zmq_unbind"
    c_zmq_unbind :: ZMQSocket -> CString -> IO CInt

foreign import ccall unsafe "zmq.h zmq_connect"
    c_zmq_connect :: ZMQSocket -> CString -> IO CInt

foreign import ccall unsafe "zmq.h zmq_sendmsg"
    c_zmq_sendmsg :: ZMQSocket -> ZMQMsgPtr -> CInt -> IO CInt

foreign import ccall unsafe "zmq.h zmq_recvmsg"
    c_zmq_recvmsg :: ZMQSocket -> ZMQMsgPtr -> CInt -> IO CInt

foreign import ccall unsafe "zmq.h zmq_socket_monitor"
    c_zmq_socket_monitor :: ZMQSocket -> CString -> CInt -> IO CInt

-- errors

foreign import ccall unsafe "zmq.h zmq_errno"
    c_zmq_errno :: IO CInt

foreign import ccall unsafe "zmq.h zmq_strerror"
    c_zmq_strerror :: CInt -> IO CString

-- proxy

foreign import ccall safe "zmq.h zmq_proxy"
    c_zmq_proxy :: ZMQSocket -> ZMQSocket -> ZMQSocket -> IO CInt

-- poll

foreign import ccall safe "zmq.h zmq_poll"
    c_zmq_poll :: ZMQPollPtr -> CInt -> CLong -> IO CInt

-- Z85 encode/decode

foreign import ccall unsafe "zmq.h zmq_z85_encode"
    c_zmq_z85_encode :: CString -> Ptr Word8 -> CSize -> IO CString

foreign import ccall unsafe "zmq.h zmq_z85_decode"
    c_zmq_z85_decode :: Ptr Word8 -> CString -> IO (Ptr Word8)

-- curve crypto

foreign import ccall unsafe "zmq.h zmq_curve_keypair"
    c_zmq_curve_keypair :: CString -> CString -> IO CInt

