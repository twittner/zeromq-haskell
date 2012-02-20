{-# LANGUAGE CPP, ForeignFunctionInterface #-}
-- |
-- Module      : System.ZMQ3.Base
-- Copyright   : (c) 2010-2012 Toralf Wittner
-- License     : MIT
-- Maintainer  : toralf.wittner@gmail.com
-- Stability   : experimental
-- Portability : non-portable
--

module System.ZMQ3.Base where

import Foreign
import Foreign.C.Types
import Foreign.C.String
import Control.Applicative

#include <zmq.h>

#if ZMQ_VERSION_MAJOR != 3
    #error *** INVALID 0MQ VERSION (must be 3.x) ***
#endif

newtype ZMQMsg = ZMQMsg { content :: Ptr () }

instance Storable ZMQMsg where
    alignment _        = #{alignment zmq_msg_t}
    sizeOf    _        = #{size zmq_msg_t}
    peek p             = ZMQMsg <$> #{peek zmq_msg_t, _} p
    poke p (ZMQMsg c)  = #{poke zmq_msg_t, _} p c

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
  , dealer     = ZMQ_DEALER
  , router     = ZMQ_ROUTER
  , pull       = ZMQ_PULL
  , push       = ZMQ_PUSH
}

newtype ZMQOption = ZMQOption { optVal :: CInt } deriving (Eq, Ord)

#{enum ZMQOption, ZMQOption
  , affinity        = ZMQ_AFFINITY
  , backlog         = ZMQ_BACKLOG
  , events          = ZMQ_EVENTS
  , filedesc        = ZMQ_FD
  , identity        = ZMQ_IDENTITY
  , ipv4Only        = ZMQ_IPV4ONLY
  , linger          = ZMQ_LINGER
  , maxMessageSize  = ZMQ_MAXMSGSIZE
  , mcastHops       = ZMQ_MULTICAST_HOPS
  , rate            = ZMQ_RATE
  , receiveBuf      = ZMQ_RCVBUF
  , receiveHighWM   = ZMQ_RCVHWM
  , receiveMore     = ZMQ_RCVMORE
  , receiveTimeout  = ZMQ_RCVTIMEO
  , reconnectIVL    = ZMQ_RECONNECT_IVL
  , reconnectIVLMax = ZMQ_RECONNECT_IVL_MAX
  , recoveryIVL     = ZMQ_RECOVERY_IVL
  , sendBuf         = ZMQ_SNDBUF
  , sendHighWM      = ZMQ_SNDHWM
  , sendTimeout     = ZMQ_SNDTIMEO
  , subscribe       = ZMQ_SUBSCRIBE
  , unsubscribe     = ZMQ_UNSUBSCRIBE
}

newtype ZMQMsgOption = ZMQMsgOption { msgOptVal :: CInt } deriving (Eq, Ord)

#{enum ZMQMsgOption, ZMQMsgOption
  , more = ZMQ_MORE
}

newtype ZMQFlag = ZMQFlag { flagVal :: CInt } deriving (Eq, Ord)

#{enum ZMQFlag, ZMQFlag
  , dontWait = ZMQ_DONTWAIT
  , sndMore  = ZMQ_SNDMORE
}

newtype ZMQPollEvent = ZMQPollEvent { pollVal :: CShort } deriving (Eq, Ord)

#{enum ZMQPollEvent, ZMQPollEvent,
    pollIn    = ZMQ_POLLIN,
    pollOut   = ZMQ_POLLOUT,
    pollerr   = ZMQ_POLLERR,
    pollInOut = ZMQ_POLLIN | ZMQ_POLLOUT
}

-- general initialization

foreign import ccall unsafe "zmq.h zmq_version"
    c_zmq_version :: Ptr CInt -> Ptr CInt -> Ptr CInt -> IO ()

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

foreign import ccall unsafe "zmq.h zmq_msg_get"
    c_zmq_msg_get :: ZMQMsgPtr
                    -> CInt      -- option
                    -> Ptr ()    -- option value
                    -> Ptr CSize -- option value size ptr
                    -> IO CInt

foreign import ccall unsafe "zmq.h zmq_msg_set"
    c_zmq_msg_set :: ZMQMsgPtr
                    -> CInt      -- option
                    -> Ptr ()    -- option value
                    -> Ptr CSize -- option value size ptr
                    -> IO CInt
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

foreign import ccall unsafe "zmq.h zmq_sendmsg"
    c_zmq_sendmsg :: ZMQSocket -> ZMQMsgPtr -> CInt -> IO CInt

foreign import ccall unsafe "zmq.h zmq_recvmsg"
    c_zmq_recvmsg :: ZMQSocket -> ZMQMsgPtr -> CInt -> IO CInt

-- error messages

foreign import ccall unsafe "zmq.h zmq_strerror"
    c_zmq_strerror :: CInt -> IO CString

