{-# LANGUAGE CPP, ForeignFunctionInterface #-}
-- |
-- Module      : System.ZMQ.Base
-- Copyright   : (c) 2010-2011 Toralf Wittner
-- License     : MIT
-- Maintainer  : toralf.wittner@gmail.com
-- Stability   : experimental
-- Portability : non-portable
--

module System.ZMQ.Base where

import Foreign
import Foreign.C.Types
import Foreign.C.String
import Control.Applicative

#include <zmq.h>

zmqVersion :: (Int, Int, Int)
zmqVersion = ( #const ZMQ_VERSION_MAJOR
             , #const ZMQ_VERSION_MINOR
             , #const ZMQ_VERSION_PATCH )

newtype ZMQMsg = ZMQMsg { content :: Ptr () }

instance Storable ZMQMsg where
    alignment _        = #{alignment zmq_msg_t}
    sizeOf    _        = #{size zmq_msg_t}
#ifdef ZMQ2
    peek p             = ZMQMsg <$> #{peek zmq_msg_t, content} p
    poke p (ZMQMsg c)  = #{poke zmq_msg_t, content} p c
#endif
#ifdef ZMQ3
    peek p             = ZMQMsg <$> #{peek zmq_msg_t, _} p
    poke p (ZMQMsg c)  = #{poke zmq_msg_t, _} p c
#endif

data ZMQPoll = ZMQPoll
    { pSocket  :: ZMQSocket
    , pFd      :: CInt
    , pEvents  :: CShort
    , pRevents :: CShort
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

newtype ZMQSocketType = ZMQSocketType { typeVal :: CInt } deriving (Eq, Ord)

#{enum ZMQSocketType, ZMQSocketType
  , pair       = ZMQ_PAIR
  , pub        = ZMQ_PUB
  , sub        = ZMQ_SUB
  , xpub       = ZMQ_XPUB
  , xsub       = ZMQ_XSUB
  , request    = ZMQ_REQ
  , response   = ZMQ_REP
  , xrequest   = ZMQ_XREQ
  , xresponse  = ZMQ_XREP
  , pull       = ZMQ_PULL
  , push       = ZMQ_PUSH
#ifdef ZMQ2
  , upstream   = ZMQ_UPSTREAM
  , downstream = ZMQ_DOWNSTREAM
#endif
}

newtype ZMQOption = ZMQOption { optVal :: CInt } deriving (Eq, Ord)

#{enum ZMQOption, ZMQOption
  , affinity        = ZMQ_AFFINITY
  , backlog         = ZMQ_BACKLOG
  , events          = ZMQ_EVENTS
  , filedesc        = ZMQ_FD
  , identity        = ZMQ_IDENTITY
  , linger          = ZMQ_LINGER
  , rate            = ZMQ_RATE
  , receiveBuf      = ZMQ_RCVBUF
  , receiveMore     = ZMQ_RCVMORE
  , reconnectIVL    = ZMQ_RECONNECT_IVL
  , reconnectIVLMax = ZMQ_RECONNECT_IVL_MAX
  , recoveryIVL     = ZMQ_RECOVERY_IVL
  , sendBuf         = ZMQ_SNDBUF
  , subscribe       = ZMQ_SUBSCRIBE
  , unsubscribe     = ZMQ_UNSUBSCRIBE
#ifdef ZMQ2
  , highWM          = ZMQ_HWM
  , mcastLoop       = ZMQ_MCAST_LOOP
  , recoveryIVLMsec = ZMQ_RECOVERY_IVL_MSEC
  , swap            = ZMQ_SWAP
#endif
#ifdef ZMQ3
  , ipv4Only        = ZMQ_IPV4ONLY
  , maxMessageSize  = ZMQ_MAXMSGSIZE
  , mcastHops       = ZMQ_MULTICAST_HOPS
  , receiveHighWM   = ZMQ_RCVHWM
  , receiveTimeout  = ZMQ_RCVTIMEO
  , sendHighWM      = ZMQ_SNDHWM
  , sendTimeout     = ZMQ_SNDTIMEO
#endif
}

#ifdef ZMQ3
newtype ZMQMsgOption = ZMQMsgOption { msgOptVal :: CInt } deriving (Eq, Ord)

#{enum ZMQMsgOption, ZMQMsgOption
  , more = ZMQ_MORE
}
#endif

newtype ZMQFlag = ZMQFlag { flagVal :: CInt } deriving (Eq, Ord)

#ifdef ZMQ2
#{enum ZMQFlag, ZMQFlag
  , noBlock = ZMQ_NOBLOCK
  , sndMore = ZMQ_SNDMORE
}
#endif
#ifdef ZMQ3
#{enum ZMQFlag, ZMQFlag
  , noBlock = ZMQ_DONTWAIT
  , sndMore = ZMQ_SNDMORE
}
#endif

newtype ZMQPollEvent = ZMQPollEvent { pollVal :: CShort } deriving (Eq, Ord)

#{enum ZMQPollEvent, ZMQPollEvent,
    pollIn    = ZMQ_POLLIN,
    pollOut   = ZMQ_POLLOUT,
    pollerr   = ZMQ_POLLERR,
    pollInOut = ZMQ_POLLIN | ZMQ_POLLOUT
}


#ifdef ZMQ2
newtype ZMQDevice = ZMQDevice { deviceType :: CInt } deriving (Eq, Ord)

#{enum ZMQDevice, ZMQDevice,
    deviceStreamer  = ZMQ_STREAMER,
    deviceForwarder = ZMQ_FORWARDER,
    deviceQueue     = ZMQ_QUEUE
}

foreign import ccall safe "zmq.h zmq_device"
    c_zmq_device :: CInt -> ZMQSocket -> ZMQSocket -> IO CInt
#endif

-- general initialization

foreign import ccall unsafe "zmq.h zmq_init"
    c_zmq_init :: CInt -> IO ZMQCtx

foreign import ccall unsafe "zmq.h zmq_term"
    c_zmq_term :: ZMQCtx -> IO CInt

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

foreign import ccall unsafe "zmq.h zmq_connect"
    c_zmq_connect :: ZMQSocket -> CString -> IO CInt


#ifdef ZMQ2
foreign import ccall unsafe "zmq.h zmq_send"
    c_zmq_send :: ZMQSocket -> ZMQMsgPtr -> CInt -> IO CInt

foreign import ccall unsafe "zmq.h zmq_recv"
    c_zmq_recv :: ZMQSocket -> ZMQMsgPtr -> CInt -> IO CInt
#endif
#ifdef ZMQ3
foreign import ccall unsafe "zmq.h zmq_sendmsg"
    c_zmq_send :: ZMQSocket -> ZMQMsgPtr -> CInt -> IO CInt

foreign import ccall unsafe "zmq.h zmq_recvmsg"
    c_zmq_recv :: ZMQSocket -> ZMQMsgPtr -> CInt -> IO CInt

foreign import ccall unsafe "zmq.h zmq_getmsgopt"
    c_zmq_getmsgopt :: ZMQMsgPtr
                    -> CInt      -- option
                    -> Ptr ()    -- option value
                    -> Ptr CSize -- option value size ptr
                    -> IO CInt
#endif

-- poll

foreign import ccall safe "zmq.h zmq_poll"
    c_zmq_poll :: ZMQPollPtr -> CInt -> CLong -> IO CInt

