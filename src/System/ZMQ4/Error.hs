{-# LANGUAGE DeriveDataTypeable #-}

-- We use our own functions for throwing exceptions in order to get
-- the actual error message via 'zmq_strerror'. 0MQ defines additional
-- error numbers besides those defined by the operating system, so
-- 'zmq_strerror' should be used in preference to 'strerror' which is
-- used by the standard throw* functions in 'Foreign.C.Error'.
module System.ZMQ4.Error where

import Control.Applicative
import Control.Monad
import Control.Exception
import Text.Printf
import Data.Typeable (Typeable)

import Foreign hiding (throwIf, throwIf_, void)
import Foreign.C.Error
import Foreign.C.String
import Foreign.C.Types (CInt)

import System.ZMQ4.Base

-- | ZMQError encapsulates information about errors, which occur
-- when using the native 0MQ API, such as error number and message.
data ZMQError = ZMQError
    { errno   :: Int     -- ^ Error number value.
    , source  :: String  -- ^ Source where this error originates from.
    , message :: String  -- ^ Actual error message.
    } deriving (Eq, Ord, Typeable)

instance Show ZMQError where
    show e = printf "ZMQError { errno = %d, source = \"%s\", message = \"%s\" }"
                (errno e) (source e) (message e)

instance Exception ZMQError

throwError :: String -> IO a
throwError src = do
    (Errno e) <- zmqErrno
    msg       <- zmqErrnoMessage e
    throwIO $ ZMQError (fromIntegral e) src msg

throwIf :: (a -> Bool) -> String -> IO a -> IO a
throwIf p src act = do
    r <- act
    if p r then throwError src else return r

throwIf_ :: (a -> Bool) -> String -> IO a -> IO ()
throwIf_ p src act = void $ throwIf p src act

throwIfRetry :: (a -> Bool) -> String -> IO a -> IO a
throwIfRetry p src act = do
    r <- act
    if p r then zmqErrno >>= k else return r
  where
    k e | e == eINTR = throwIfRetry p src act
        | otherwise  = throwError src

throwIfRetry_ :: (a -> Bool) -> String -> IO a -> IO ()
throwIfRetry_ p src act = void $ throwIfRetry p src act

throwIfMinus1 :: (Eq a, Num a) => String -> IO a -> IO a
throwIfMinus1 = throwIf (== -1)

throwIfMinus1_ :: (Eq a, Num a) => String -> IO a -> IO ()
throwIfMinus1_ = throwIf_ (== -1)

throwIfNull :: String -> IO (Ptr a) -> IO (Ptr a)
throwIfNull = throwIf (== nullPtr)

throwIfMinus1Retry :: (Eq a, Num a) => String -> IO a -> IO a
throwIfMinus1Retry = throwIfRetry (== -1)

throwIfMinus1Retry_ :: (Eq a, Num a) => String -> IO a -> IO ()
throwIfMinus1Retry_ = throwIfRetry_ (== -1)

throwIfRetryMayBlock :: (a -> Bool) -> String -> IO a -> IO b -> IO a
throwIfRetryMayBlock p src f on_block = do
    r <- f
    if p r then zmqErrno >>= k else return r
  where
    k e | e == eINTR                      = throwIfRetryMayBlock p src f on_block
        | e == eWOULDBLOCK || e == eAGAIN = on_block >> throwIfRetryMayBlock p src f on_block
        | otherwise                       = throwError src

throwIfRetryMayBlock_ :: (a -> Bool) -> String -> IO a -> IO b -> IO ()
throwIfRetryMayBlock_ p src f on_block = void $ throwIfRetryMayBlock p src f on_block

throwIfMinus1RetryMayBlock :: (Eq a, Num a) => String -> IO a -> IO b -> IO a
throwIfMinus1RetryMayBlock = throwIfRetryMayBlock (== -1)

throwIfMinus1RetryMayBlock_ :: (Eq a, Num a) => String -> IO a -> IO b -> IO ()
throwIfMinus1RetryMayBlock_ = throwIfRetryMayBlock_ (== -1)

zmqErrnoMessage :: CInt -> IO String
zmqErrnoMessage e = c_zmq_strerror e >>= peekCString

zmqErrno :: IO Errno
zmqErrno = Errno <$> c_zmq_errno
