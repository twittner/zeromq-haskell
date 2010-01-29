{-# LANGUAGE CPP, ForeignFunctionInterface #-}
-- |
-- Module      : System.ZMQ.Base
-- Copyright   : (c) 2010 Toralf Wittner
-- License     : LGPL
-- Maintainer  : toralf.wittner@gmail.com
-- Stability   : experimental
-- Portability : non-portable
-- 

module System.ZMQ.Base where

import Control.Applicative
import Foreign
import Foreign.C.Types
import Foreign.C.String

#include <zmq.h>

newtype ZMQMsg = ZMQMsg { content :: Ptr () }

instance Storable ZMQMsg where
    alignment _        = #{alignment zmq_msg_t}
    sizeOf    _        = #{size zmq_msg_t}
    peek p             = ZMQMsg <$> #{peek zmq_msg_t, content} p
    poke p (ZMQMsg c) = #{poke zmq_msg_t, content} p c

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

usePoll :: CInt
usePoll = #const ZMQ_POLL

type ZMQMsgPtr  = Ptr ZMQMsg
type ZMQCtx     = Ptr ()
type ZMQSocket  = Ptr ()
type ZMQPollPtr = Ptr ZMQPoll

#let alignment t = "%lu", (unsigned long)offsetof(struct {char x__; t (y__); }, y__)

newtype ZMQSocketType = ZMQSocketType { typeVal :: CInt } deriving (Eq, Ord)

#{enum ZMQSocketType, ZMQSocketType,
    p2p        = ZMQ_P2P,
    pub        = ZMQ_PUB,
    sub        = ZMQ_SUB,
    request    = ZMQ_REQ,
    response   = ZMQ_REP,
    xrequest   = ZMQ_XREQ,
    xresponse  = ZMQ_XREP,
    upstream   = ZMQ_UPSTREAM,
    downstream = ZMQ_DOWNSTREAM
}

newtype ZMQOption = ZMQOption { optVal :: CInt } deriving (Eq, Ord)

#{enum ZMQOption, ZMQOption,
    highWM      = ZMQ_HWM,
    lowWM       = ZMQ_LWM,
    swap        = ZMQ_SWAP,
    affinity    = ZMQ_AFFINITY,
    identity    = ZMQ_IDENTITY,
    subscribe   = ZMQ_SUBSCRIBE,
    unsubscribe = ZMQ_UNSUBSCRIBE,
    rate        = ZMQ_RATE,
    recoveryIVL = ZMQ_RECOVERY_IVL,
    mcastLoop   = ZMQ_MCAST_LOOP,
    sendBuf     = ZMQ_SNDBUF,
    receiveBuf  = ZMQ_RCVBUF
}

newtype ZMQFlag = ZMQFlag { flagVal :: CInt } deriving (Eq, Ord)

#{enum ZMQFlag, ZMQFlag,
    noBlock = ZMQ_NOBLOCK,
    noFlush = ZMQ_NOFLUSH
}

newtype ZMQPollEvent = ZMQPollEvent { pollVal :: CShort } deriving (Eq, Ord)

#{enum ZMQPollEvent, ZMQPollEvent,
    pollIn    = ZMQ_POLLIN,
    pollOut   = ZMQ_POLLOUT,
    pollInOut = ZMQ_POLLIN | ZMQ_POLLOUT
}

-- general initialization

foreign import ccall unsafe "zmq.h zmq_init"
    c_zmq_init :: CInt -> CInt -> CInt -> IO ZMQCtx

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

foreign import ccall unsafe "zmq.h zmq_bind"
    c_zmq_bind :: ZMQSocket -> CString -> IO CInt

foreign import ccall unsafe "zmq.h zmq_connect"
    c_zmq_connect :: ZMQSocket -> CString -> IO CInt

foreign import ccall unsafe "zmq.h zmq_send"
    c_zmq_send :: ZMQSocket -> ZMQMsgPtr -> CInt -> IO CInt

foreign import ccall unsafe "zmq.h zmq_flush"
    c_zmq_flush :: ZMQSocket -> IO CInt

foreign import ccall unsafe "zmq.h zmq_recv"
    c_zmq_recv :: ZMQSocket -> ZMQMsgPtr -> CInt -> IO CInt

-- poll

foreign import ccall unsafe "zmq.h zmq_poll"
    c_zmq_poll :: ZMQPollPtr -> CInt -> CLong -> IO CInt

