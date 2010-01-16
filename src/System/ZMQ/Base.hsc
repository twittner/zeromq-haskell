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

data Message a = Message { content :: Ptr a }

instance Storable (Message a) where
    alignment _       = #{alignment zmq_msg_t}
    sizeOf    _       = #{size zmq_msg_t}
    peek p            = Message <$> #{peek zmq_msg_t, content} p
    poke p (Message c) = #{poke zmq_msg_t, content} p c

data Poll = Poll
    { pSocket  :: ZMQSocket
    , pFd      :: CInt
    , pEvents  :: CShort
    , pRevents :: CShort
    }

instance Storable Poll where
    alignment _ = #{alignment zmq_pollitem_t}
    sizeOf    _ = #{size zmq_pollitem_t}
    peek p = do
        s  <- #{peek zmq_pollitem_t, socket} p
        f  <- #{peek zmq_pollitem_t, fd} p
        e  <- #{peek zmq_pollitem_t, events} p
        re <- #{peek zmq_pollitem_t, revents} p
        return $ Poll s f e re
    poke p (Poll s f e re) = do
        #{poke zmq_pollitem_t, socket} p s
        #{poke zmq_pollitem_t, fd} p f
        #{poke zmq_pollitem_t, events} p e
        #{poke zmq_pollitem_t, revents} p re

type ZMQMsgPtr a  = Ptr (Message a)
type ZMQFun       = FunPtr (Ptr () -> Ptr () -> IO ())
type ZMQCtx       = Ptr ()
type ZMQSocket    = Ptr ()
type ZMQPollPtr   = Ptr Poll
type ZMQStopWatch = Ptr ()

#let alignment t = "%lu", (unsigned long)offsetof(struct {char x__; t (y__); }, y__)

newtype CSocketType = CSocketType { typeVal :: CInt } deriving (Eq, Ord)

#{enum CSocketType, CSocketType,
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

newtype OptionType = OptionType { optVal :: CInt } deriving (Eq, Ord)

#{enum OptionType, OptionType,
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

newtype CFlag = CFlag { flagVal :: CInt } deriving (Eq, Ord)

#{enum CFlag, CFlag,
    noBlock = ZMQ_NOBLOCK,
    noFlush = ZMQ_NOFLUSH
}

-- general initialization

foreign import ccall unsafe "zmq.h zmq_init"
    c_zmq_init :: CInt -> CInt -> CInt -> IO ZMQCtx

foreign import ccall unsafe "zmq.h zmq_term"
    c_zmq_term :: ZMQCtx -> IO CInt

-- zmq_msg_t related

foreign import ccall unsafe "zmq.h zmq_msg_init"
    c_zmq_msg_init :: ZMQMsgPtr a -> IO CInt

foreign import ccall unsafe "zmq.h zmq_msg_init_size"
    c_zmq_msg_init_size :: ZMQMsgPtr a -> CSize -> IO CInt

foreign import ccall unsafe "zmq.h zmq_msg_init_data"
    c_zmq_msg_init_data :: ZMQMsgPtr a
                        -> Ptr ()  -- ^ msg
                        -> CSize   -- ^ size
                        -> ZMQFun  -- ^ free function
                        -> Ptr ()  -- ^ hint
                        -> IO CInt

foreign import ccall unsafe "zmq.h zmq_msg_close"
    c_zmq_msg_close :: ZMQMsgPtr a -> IO CInt

foreign import ccall unsafe "zmq.h zmq_msg_move"
    c_zmq_msg_move :: ZMQMsgPtr a -> ZMQMsgPtr a -> IO CInt

foreign import ccall unsafe "zmq.h zmq_msg_copy"
    c_zmq_msg_copy :: ZMQMsgPtr a -> ZMQMsgPtr a -> IO CInt

foreign import ccall unsafe "zmq.h zmq_msg_data"
    c_zmq_msg_data :: ZMQMsgPtr a -> IO (Ptr a)

foreign import ccall unsafe "zmq.h zmq_msg_size"
    c_zmq_msg_size :: ZMQMsgPtr a -> IO CInt

-- socket

foreign import ccall unsafe "zmq.h zmq_socket"
    c_zmq_socket :: ZMQCtx -> CInt -> IO ZMQSocket

foreign import ccall unsafe "zmq.h zmq_close"
    c_zmq_close :: ZMQSocket -> IO CInt

foreign import ccall unsafe "zmq.h zmq_setsockopt"
    c_zmq_setsockopt :: ZMQSocket
                     -> CInt   -- ^ option
                     -> Ptr () -- ^ option value
                     -> CSize  -- ^ option value size
                     -> IO CInt

foreign import ccall unsafe "zmq.h zmq_bind"
    c_zmq_bind :: ZMQSocket -> CString -> IO CInt

foreign import ccall unsafe "zmq.h zmq_connect"
    c_zmq_connect :: ZMQSocket -> CString -> IO CInt

foreign import ccall unsafe "zmq.h zmq_send"
    c_zmq_send :: ZMQSocket -> ZMQMsgPtr a -> CInt -> IO CInt

foreign import ccall unsafe "zmq.h zmq_flush"
    c_zmq_flush :: ZMQSocket -> IO CInt

foreign import ccall unsafe "zmq.h zmq_recv"
    c_zmq_recv :: ZMQSocket -> ZMQMsgPtr a -> CInt -> IO CInt

-- poll

foreign import ccall unsafe "zmq.h zmq_poll"
    c_zmq_poll :: ZMQPollPtr -> CInt -> CLong -> IO CInt


-- utility

foreign import ccall unsafe "zmq.h zmq_strerror"
    c_zmq_strerror :: CInt -> IO CString

foreign import ccall unsafe "zmq.h zmq_stopwatch_start"
    c_zmq_stopwatch_start :: IO ZMQStopWatch

foreign import ccall unsafe "zmq.h zmq_stopwatch_stop"
    c_zmq_stopwatch_stop :: ZMQStopWatch -> IO CULong

foreign import ccall unsafe "zmq.h zmq_sleep"
    c_zmq_sleep :: CInt -> IO ()

