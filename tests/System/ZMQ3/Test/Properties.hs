{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE OverloadedStrings    #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
module System.ZMQ3.Test.Properties where

import Test.QuickCheck
import Test.QuickCheck.Checkers
import Test.QuickCheck.Classes
import Test.QuickCheck.Monadic
import Test.Tools

import Control.Applicative
import Data.Int
import Data.Word
import Data.Restricted
import Data.Maybe (fromJust)
import Data.ByteString (ByteString)
import Control.Concurrent
import System.ZMQ3.Monadic
import System.Posix.Types (Fd(..))
import qualified Data.ByteString as SB
import qualified Data.ByteString.Char8 as CB

tests :: IO ()
tests = do
      quickBatch' ("0MQ Socket Properties"
        , [ ("get socket option (Pair)",       property $ prop_get_socket_option Pair)
          , ("get socket option (Pub)",        property $ prop_get_socket_option Pub)
          , ("get socket option (Sub)",        property $ prop_get_socket_option Sub)
          , ("get socket option (XPub)",       property $ prop_get_socket_option XPub)
          , ("get socket option (XSub)",       property $ prop_get_socket_option XSub)
          , ("get socket option (Req)",        property $ prop_get_socket_option Req)
          , ("get socket option (Rep)",        property $ prop_get_socket_option Rep)
          , ("get socket option (Dealer)",     property $ prop_get_socket_option Dealer)
          , ("get socket option (Router)",     property $ prop_get_socket_option Router)
          , ("get socket option (Pull)",       property $ prop_get_socket_option Pull)
          , ("get socket option (Push)",       property $ prop_get_socket_option Push)
          , ("set;get socket option (Pair)",   property $ prop_set_get_socket_option Pair)
          , ("set;get socket option (Pub)",    property $ prop_set_get_socket_option Pub)
          , ("set;get socket option (Sub)",    property $ prop_set_get_socket_option Sub)
          , ("set;get socket option (XPub)",   property $ prop_set_get_socket_option XPub)
          , ("set;get socket option (XSub)",   property $ prop_set_get_socket_option XSub)
          , ("set;get socket option (Req)",    property $ prop_set_get_socket_option Req)
          , ("set;get socket option (Rep)",    property $ prop_set_get_socket_option Rep)
          , ("set;get socket option (Dealer)", property $ prop_set_get_socket_option Dealer)
          , ("set;get socket option (Router)", property $ prop_set_get_socket_option Router)
          , ("set;get socket option (Pull)",   property $ prop_set_get_socket_option Pull)
          , ("set;get socket option (Push)",   property $ prop_set_get_socket_option Push)
          , ("(un-)subscribe",                 property $ prop_subscribe Sub)
          ])

      quickBatch' ("0MQ Messages"
        , [ ("msg send == msg received (Req/Rep)",   property $ prop_send_receive Req Rep)
          , ("msg send == msg received (Push/Pull)", property $ prop_send_receive Push Pull)
          , ("msg send == msg received (Pair/Pair)", property $ prop_send_receive Pair Pair)

          -- , ("publish/subscribe", prop_pub_sub Pub Sub)
          -- (Disabled due to LIBZMQ-270 [https://zeromq.jira.com/browse/LIBZMQ-270].)
          ])

      quickBatch' prop_zmq_functor
      quickBatch' prop_zmq_monad

prop_get_socket_option :: SocketType t => t -> GetOpt -> Property
prop_get_socket_option t opt = monadicIO $ run $ do
    runZMQ $ do
        s <- socket t
        case opt of
            Events _      -> events s         >> return ()
            Filedesc _    -> fileDescriptor s >> return ()
            ReceiveMore _ -> moreToReceive s  >> return ()

prop_set_get_socket_option :: SocketType t => t -> SetOpt -> Property
prop_set_get_socket_option t opt = monadicIO $ do
    r <- run $ runZMQ $ do
        s <- socket t
        case opt of
            Identity val        -> (== (rvalue val)) <$> (setIdentity val s >> identity s)
            Ipv4Only val        -> (== val)          <$> (setIpv4Only val s >> ipv4Only s)
            Affinity val        -> (ieq val)          <$> (setAffinity val s >> affinity s)
            Backlog val         -> (ieq (rvalue val)) <$> (setBacklog val s >> backlog s)
            Linger val          -> (ieq (rvalue val)) <$> (setLinger val s >> linger s)
            Rate val            -> (ieq (rvalue val)) <$> (setRate val s >> rate s)
            ReceiveBuf val      -> (ieq (rvalue val)) <$> (setReceiveBuffer val s >> receiveBuffer s)
            ReconnectIVL val    -> (ieq (rvalue val)) <$> (setReconnectInterval val s >> reconnectInterval s)
            ReconnectIVLMax val -> (ieq (rvalue val)) <$> (setReconnectIntervalMax val s >> reconnectIntervalMax s)
            RecoveryIVL val     -> (ieq (rvalue val)) <$> (setRecoveryInterval val s >> recoveryInterval s)
            SendBuf val         -> (ieq (rvalue val)) <$> (setSendBuffer val s >> sendBuffer s)
            MaxMessageSize val  -> (ieq (rvalue val)) <$> (setMaxMessageSize val s >> maxMessageSize s)
            McastHops val       -> (ieq (rvalue val)) <$> (setMcastHops val s >> mcastHops s)
            ReceiveHighWM val   -> (ieq (rvalue val)) <$> (setReceiveHighWM val s >> receiveHighWM s)
            ReceiveTimeout val  -> (ieq (rvalue val)) <$> (setReceiveTimeout val s >> receiveTimeout s)
            SendHighWM val      -> (ieq (rvalue val)) <$> (setSendHighWM val s >> sendHighWM s)
            SendTimeout val     -> (ieq (rvalue val)) <$> (setSendTimeout val s >> sendTimeout s)
    assert r
  where
    ieq :: (Integral i, Integral k) => i -> k -> Bool
    ieq i k  = (fromIntegral i :: Int) == (fromIntegral k :: Int)

prop_subscribe :: (Subscriber a, SocketType a) => a -> ByteString -> Property
prop_subscribe t subs = monadicIO $ run $
    runZMQ $ do
        s <- socket t
        subscribe s subs
        unsubscribe s subs

prop_send_receive :: (SocketType a, SocketType b, Receiver b, Sender a) => a -> b -> ByteString -> Property
prop_send_receive a b msg = monadicIO $ do
    msg' <- run $ runZMQ $ do
        sender   <- socket a
        receiver <- socket b
        sync     <- liftIO newEmptyMVar
        bind receiver "inproc://endpoint"
        async $ receive receiver >>= liftIO . putMVar sync
        connect sender "inproc://endpoint"
        send sender [] msg
        liftIO $ takeMVar sync
    assert (msg == msg')

prop_pub_sub :: (SocketType a, Subscriber b, SocketType b, Sender a, Receiver b) => a -> b -> ByteString -> Property
prop_pub_sub a b msg = monadicIO $ do
    msg' <- run $ runZMQ $ do
        pub <- socket a
        sub <- socket b
        subscribe sub ""
        bind sub "inproc://endpoint"
        connect pub "inproc://endpoint"
        send pub [] msg
        receive sub
    assert (msg == msg')

prop_zmq_functor :: TestBatch
prop_zmq_functor = functor (undefined :: ZMQ (Int, Int, Int))

prop_zmq_monad :: TestBatch
prop_zmq_monad = monad (undefined :: ZMQ (Int, Int, Int))

instance Arbitrary ByteString where
    arbitrary = CB.pack . filter (/= '\0') <$> arbitrary

instance Arbitrary (ZMQ Int) where
    arbitrary = return <$> arbitrary

instance Show (ZMQ Int) where
    show _ = "zmq"

instance (Eq a, EqProp a) => EqProp (ZMQ a) where
    za =-= zb = monadicIO $ run (eq <$> runZMQ za <*> runZMQ zb)

data GetOpt =
    Events          Int
  | Filedesc        Fd
  | ReceiveMore     Bool
  deriving Show

data SetOpt =
    Affinity        Word64
  | Backlog         (Restricted N0 Int32 Int)
  | Identity        (Restricted N1 N254 ByteString)
  | Ipv4Only        Bool
  | Linger          (Restricted Nneg1 Int32 Int)
  | MaxMessageSize  (Restricted Nneg1 Int64 Int64)
  | McastHops       (Restricted N1 Int32 Int)
  | Rate            (Restricted N1 Int32 Int)
  | ReceiveBuf      (Restricted N0 Int32 Int)
  | ReceiveHighWM   (Restricted N0 Int32 Int)
  | ReceiveTimeout  (Restricted Nneg1 Int32 Int)
  | ReconnectIVL    (Restricted N0 Int32 Int)
  | ReconnectIVLMax (Restricted N0 Int32 Int)
  | RecoveryIVL     (Restricted N0 Int32 Int)
  | SendBuf         (Restricted N0 Int32 Int)
  | SendHighWM      (Restricted N0 Int32 Int)
  | SendTimeout     (Restricted Nneg1 Int32 Int)
  deriving Show

instance Arbitrary GetOpt where
    arbitrary = oneof [
        Events                       <$> arbitrary
      , Filedesc . Fd . fromIntegral <$> (arbitrary :: Gen Int32)
      , ReceiveMore                  <$> arbitrary
      ]

instance Arbitrary SetOpt where
    arbitrary = oneof [
        Affinity                   <$> (arbitrary :: Gen Word64)
      , Ipv4Only                   <$> (arbitrary :: Gen Bool)
      , Backlog         . toR0     <$> (arbitrary :: Gen Int32) `suchThat` (>=  0)
      , Linger          . toRneg1  <$> (arbitrary :: Gen Int32) `suchThat` (>= -1)
      , Rate            . toR1     <$> (arbitrary :: Gen Int32) `suchThat` (>   0)
      , ReceiveBuf      . toR0     <$> (arbitrary :: Gen Int32) `suchThat` (>=  0)
      , ReconnectIVL    . toR0     <$> (arbitrary :: Gen Int32) `suchThat` (>=  0)
      , ReconnectIVLMax . toR0     <$> (arbitrary :: Gen Int32) `suchThat` (>=  0)
      , RecoveryIVL     . toR0     <$> (arbitrary :: Gen Int32) `suchThat` (>=  0)
      , SendBuf         . toR0     <$> (arbitrary :: Gen Int32) `suchThat` (>=  0)
      , McastHops       . toR1     <$> (arbitrary :: Gen Int32) `suchThat` (>   0)
      , ReceiveHighWM   . toR0     <$> (arbitrary :: Gen Int32) `suchThat` (>=  0)
      , ReceiveTimeout  . toRneg1  <$> (arbitrary :: Gen Int32) `suchThat` (>= -1)
      , SendHighWM      . toR0     <$> (arbitrary :: Gen Int32) `suchThat` (>=  0)
      , SendTimeout     . toRneg1  <$> (arbitrary :: Gen Int32) `suchThat` (>= -1)
      , MaxMessageSize  . toRneg1' <$> (arbitrary :: Gen Int64) `suchThat` (>= -1)
      , Identity . fromJust . toRestricted <$> arbitrary `suchThat` (\s -> SB.length s > 0 && SB.length s < 255)
      ]

toR1 :: Int32 -> Restricted N1 Int32 Int
toR1 = fromJust . toRestricted . fromIntegral

toR0 :: Int32 -> Restricted N0 Int32 Int
toR0 = fromJust . toRestricted . fromIntegral

toRneg1 :: Int32 -> Restricted Nneg1 Int32 Int
toRneg1 = fromJust . toRestricted . fromIntegral

toRneg1' :: Int64 -> Restricted Nneg1 Int64 Int64
toRneg1' = fromJust . toRestricted . fromIntegral
