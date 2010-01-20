{-# LANGUAGE ExistentialQuantification #-}
-- |
-- Module      : System.ZMQ
-- Copyright   : (c) 2010 Toralf Wittner
-- License     : LGPL
-- Maintainer  : toralf.wittner@gmail.com
-- Stability   : experimental
-- Portability : non-portable
-- 

module System.ZMQ (

    Size,
    Context,
    Socket,
    Flag(..),
    SocketOption(..),
    Poll(..),
    PollEvent(..),

    P2P(..),
    Pub(..),
    Sub(..),
    Req(..),
    Rep(..),
    XReq(..),
    XRep(..),
    Up(..),
    Down(..),

    init,
    term,

    socket,
    close,
    setOption,
    System.ZMQ.subscribe,
    System.ZMQ.unsubscribe,
    bind,
    connect,
    send,
    flush,
    receive,

    poll

) where

import Prelude hiding (init)
import Control.Applicative
import Control.Exception
import Data.Binary
import Data.Int
import System.ZMQ.Base
import qualified System.ZMQ.Base as B
import Foreign
import Foreign.C.Error
import Foreign.C.String
import Foreign.C.Types (CInt, CShort)
import qualified Data.ByteString as SB
import qualified Data.ByteString.Lazy as LB
import qualified Data.ByteString.Unsafe as UB
import System.Posix.Types (Fd(..))

-- ^ A 0MQ context representation.
newtype Context = Context { ctx :: ZMQCtx }

-- ^ A 0MQ Socket.
newtype Socket a = Socket { sock :: ZMQSocket }

-- A 0MQ Message representation.
newtype Message = Message { msgPtr :: ZMQMsgPtr }

type Timeout = Int64
type Size    = Word

-- Socket types:

class SType a where
    zmqSocketType :: a -> ZMQSocketType

data P2P = P2P
instance SType P2P where
    zmqSocketType = const p2p

data Pub = Pub
instance SType Pub where
    zmqSocketType = const pub

data Sub = Sub
instance SType Sub where
    zmqSocketType = const sub

data Req = Req
instance SType Req where
    zmqSocketType = const request

data Rep = Rep
instance SType Rep where
    zmqSocketType = const response

data XReq = Xreq
instance SType XReq where
    zmqSocketType = const xrequest

data XRep = Xrep
instance SType XRep where
    zmqSocketType = const xresponse

data Up = Up
instance SType Up where
    zmqSocketType = const upstream

data Down = Down
instance SType Down where
    zmqSocketType = const downstream

-- Subscribable:

class SubsType a
instance SubsType Sub

-- ^ The option to set on 0MQ sockets (cf. man zmq_setsockopt)
data SocketOption =
    HighWM      Int64  -- ^ ZMQ_HWM
  | LowWM       Int64  -- ^ ZMQ_LWM
  | Swap        Int64  -- ^ ZMQ_SWAP
  | Affinity    Int64  -- ^ ZMQ_AFFINITY
  | Identity    String -- ^ ZMQ_IDENTITY
  | Rate        Word64 -- ^ ZMQ_RATE
  | RecoveryIVL Word64 -- ^ ZMQ_RECOVERY_IVL
  | McastLoop   Word64 -- ^ ZMQ_MCAST_LOOP
  | SendBuf     Word64 -- ^ ZMQ_SNDBUF
  | ReceiveBuf  Word64 -- ^ ZMQ_RCVBUF
  deriving (Eq, Ord, Show)

-- ^ Flags to apply on send operations (cf. man zmq_send)
data Flag =
    NoBlock -- ^ ZMQ_NOBLOCK
  | NoFlush -- ^ ZMQ_NOFLUSH
  deriving (Eq, Ord, Show)

-- ^ The events to wait for in poll (cf. man zmq_poll)
data PollEvent =
    In    -- ^ ZMQ_POLLIN
  | Out   -- ^ ZMQ_POLLOUT
  | InOut -- ^ ZMQ_POLLIN | ZMQ_POLLOUT
  deriving (Eq, Ord, Show)

-- ^ Type representing a descriptor, poll is waiting for
-- (either a 0MQ socket or a file descriptor) plus the type
-- of event of wait for.
data Poll =
    forall a. S (Socket a) PollEvent
  | F Fd PollEvent

-- ^ Initialize a 0MQ context (cf. zmq_init).
init :: Size -> Size -> Bool -> IO Context
init appThreads ioThreads doPoll = do
    c <- throwErrnoIfNull "init" $
         c_zmq_init (fromIntegral appThreads)
                    (fromIntegral ioThreads)
                    (if doPoll then usePoll else 0)
    return (Context c)

-- ^ Terminate 0MQ context (cf. zmq_term).
term :: Context -> IO ()
term = throwErrnoIfMinus1_ "term" . c_zmq_term . ctx

-- ^ Create a new 0MQ socket within the given context.
socket :: SType a => Context -> a -> IO (Socket a)
socket (Context c) t =
    let zt = typeVal . zmqSocketType $ t
    in  Socket <$> throwErrnoIfNull "socket" (c_zmq_socket c zt)

-- ^ Close a 0MQ socket.
close :: Socket a -> IO ()
close = throwErrnoIfMinus1_ "close" . c_zmq_close . sock

-- ^ Set the given option on the socket. Please note that there are
-- certain combatibility constraints w.r.t the socket type (cf. man
-- zmq_setsockopt).
--
-- Please note that subscribe/unsubscribe is handled with separate
-- functions.
setOption :: Socket a -> SocketOption -> IO ()
setOption s (HighWM o)      = setIntOpt s highWM o
setOption s (LowWM o)       = setIntOpt s lowWM o
setOption s (Swap o)        = setIntOpt s swap o
setOption s (Affinity o)    = setIntOpt s affinity o
setOption s (Identity o)    = setStrOpt s identity o
setOption s (Rate o)        = setIntOpt s rate o
setOption s (RecoveryIVL o) = setIntOpt s recoveryIVL o
setOption s (McastLoop o)   = setIntOpt s mcastLoop o
setOption s (SendBuf o)     = setIntOpt s sendBuf o
setOption s (ReceiveBuf o)  = setIntOpt s receiveBuf o

-- ^ Subscribe Socket to given subscription.
subscribe :: SubsType a => Socket a -> String -> IO ()
subscribe s = setStrOpt s B.subscribe

-- ^ Unsubscribe Socket from given subscription.
unsubscribe :: SubsType a => Socket a -> String -> IO ()
unsubscribe s = setStrOpt s B.unsubscribe

-- ^ Bind the socket to the given address (zmq_bind)
bind :: Socket a -> String -> IO ()
bind (Socket s) str = throwErrnoIfMinus1_ "bind" $
    withCString str (c_zmq_bind s)

-- ^ Connect the socket to the given address (zmq_connect).
connect :: Socket a -> String -> IO ()
connect (Socket s) str = throwErrnoIfMinus1_ "connect" $
    withCString str (c_zmq_connect s)

-- ^ Send the given 'Binary' over the socket (zmq_send).
send :: Binary b => Socket a -> b -> [Flag] -> IO ()
send (Socket s) val fls = mapM_ sendChunk (LB.toChunks . encode $ val)
 where
    sendChunk :: SB.ByteString -> IO ()
    sendChunk b = bracket (messageOf b) messageClose $ \m ->
        throwErrnoIfMinus1_ "sendChunk" $
            c_zmq_send s (msgPtr m) (combine fls)

-- ^ Flush the given socket (useful for 'send's with 'NoFlush').
flush :: Socket a -> IO ()
flush = throwErrnoIfMinus1_ "flush" . c_zmq_flush . sock

-- ^ Receive a 'Binary' from socket (zmq_recv).
receive :: Binary b => Socket a -> [Flag] -> IO b
receive (Socket s) fls = bracket messageInit messageClose $ \m -> do
    throwErrnoIfMinus1_ "receive" $ c_zmq_recv s (msgPtr m) (combine fls)
    data_ptr <- c_zmq_msg_data (msgPtr m)
    size     <- c_zmq_msg_size (msgPtr m)
    bstr     <- SB.packCStringLen (data_ptr, fromIntegral size)
    return $ decode (LB.fromChunks [bstr])

-- ^ Polls for events on the given 'Poll' descriptors. Returns the
-- list of 'Poll' descriptors for which an event occured (cf. zmq_poll).
poll :: [Poll] -> Timeout -> IO [Poll]
poll fds to = do
    let len = length fds
        ps  = map createZMQPoll fds
    withArray ps $ \ptr -> do
        throwErrnoIfMinus1_ "poll" $
            c_zmq_poll ptr (fromIntegral len) (fromIntegral to)
        ps' <- peekArray len ptr
        createPoll ps' []
 where
    createZMQPoll :: Poll -> ZMQPoll
    createZMQPoll (S (Socket s) e) =
        ZMQPoll s 0 (fromEvent e) 0
    createZMQPoll (F (Fd s) e) =
        ZMQPoll nullPtr (fromIntegral s) (fromEvent e) 0

    createPoll :: [ZMQPoll] -> [Poll] -> IO [Poll]
    createPoll []     fd = return fd
    createPoll (p:pp) fd = do
        let s = pSocket p; f = pFd p; r = pRevents p
        if r /= 0
            then if f /= 0
                    then createPoll pp (F (Fd f) (toEvent r):fd)
                    else createPoll pp fd
            else if s /= nullPtr
                    then createPoll pp (S (Socket s) (toEvent r):fd)
                    else createPoll pp fd

    fromEvent :: PollEvent -> CShort
    fromEvent In    = fromIntegral . pollVal $ pollIn
    fromEvent Out   = fromIntegral . pollVal $ pollOut
    fromEvent InOut = fromEvent In .|. fromEvent Out

    toEvent :: CShort -> PollEvent
    toEvent e | e == (fromIntegral . pollVal $ pollIn)  = In
              | e == (fromIntegral . pollVal $ pollOut) = Out
              | otherwise                                = InOut

-- internal helpers:

messageOf :: SB.ByteString -> IO Message
messageOf b = UB.unsafeUseAsCStringLen b $ \(cstr, len) -> do
    msg <- messageInitSize (fromIntegral len)
    data_ptr <- c_zmq_msg_data (msgPtr msg)
    copyBytes data_ptr cstr len
    return msg

messageClose :: Message -> IO ()
messageClose = throwErrnoIfMinus1_ "messageClose" . c_zmq_msg_close . msgPtr

messageInit :: IO Message
messageInit = do
    ptr <- new (ZMQMsg nullPtr)
    throwErrnoIfMinus1_ "messageInit" $ c_zmq_msg_init ptr
    return (Message ptr)

messageInitSize :: Size -> IO Message
messageInitSize s = do
    ptr <- new (ZMQMsg nullPtr)
    throwErrnoIfMinus1_ "messageInitSize" $
        c_zmq_msg_init_size ptr (fromIntegral s)
    return (Message ptr)

setIntOpt :: (Storable b, Integral b) => Socket a -> ZMQOption -> b -> IO ()
setIntOpt (Socket s) (ZMQOption o) i = throwErrnoIfMinus1_ "setIntOpt" $
    bracket (newStablePtr i) freeStablePtr $ \ptr ->
        c_zmq_setsockopt s (fromIntegral o)
                           (castStablePtrToPtr ptr)
                           (fromIntegral . sizeOf $ i)

setStrOpt :: Socket a -> ZMQOption -> String -> IO ()
setStrOpt (Socket s) (ZMQOption o) str = throwErrnoIfMinus1_ "setStrOpt" $
    withCStringLen str $ \(cstr, len) ->
        c_zmq_setsockopt s (fromIntegral o) (castPtr cstr) (fromIntegral len)

toZMQFlag :: Flag -> ZMQFlag
toZMQFlag NoBlock = noBlock
toZMQFlag NoFlush = noFlush

combine :: [Flag] -> CInt
combine = fromIntegral . foldr ((.|.) . flagVal . toZMQFlag) 0
