{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE OverloadedStrings    #-}
{-# LANGUAGE GADTs                #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module System.ZMQ4.Test.Properties where

import Test.QuickCheck
import Test.QuickCheck.Monadic (monadicIO, run)
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck

import Control.Applicative
import Control.Concurrent.Async (wait)
import Data.Int
import Data.Word
import Data.Restricted
import Data.Maybe (fromJust)
import Data.ByteString (ByteString)
import System.ZMQ4.Monadic
import System.Posix.Types (Fd(..))

import qualified Data.ByteString         as SB
import qualified Data.ByteString.Char8   as CB
import qualified Test.QuickCheck.Monadic as QM

tests :: TestTree
tests = testGroup "0MQ Socket Properties"
    [ testProperty "get socket option (Pair)"       (prop_get_socket_option Pair)
    , testProperty "get socket option (Pub)"        (prop_get_socket_option Pub)
    , testProperty "get socket option (Sub)"        (prop_get_socket_option Sub)
    , testProperty "get socket option (XPub)"       (prop_get_socket_option XPub)
    , testProperty "get socket option (XSub)"       (prop_get_socket_option XSub)
    , testProperty "get socket option (Req)"        (prop_get_socket_option Req)
    , testProperty "get socket option (Rep)"        (prop_get_socket_option Rep)
    , testProperty "get socket option (Dealer)"     (prop_get_socket_option Dealer)
    , testProperty "get socket option (Router)"     (prop_get_socket_option Router)
    , testProperty "get socket option (Pull)"       (prop_get_socket_option Pull)
    , testProperty "get socket option (Push)"       (prop_get_socket_option Push)
    , testProperty "set;get socket option (Pair)"   (prop_set_get_socket_option Pair)
    , testProperty "set;get socket option (Pub)"    (prop_set_get_socket_option Pub)
    , testProperty "set;get socket option (Sub)"    (prop_set_get_socket_option Sub)
    , testProperty "set;get socket option (XPub)"   (prop_set_get_socket_option XPub)
    , testProperty "set;get socket option (XSub)"   (prop_set_get_socket_option XSub)
    , testProperty "set;get socket option (Req)"    (prop_set_get_socket_option Req)
    , testProperty "set;get socket option (Rep)"    (prop_set_get_socket_option Rep)
    , testProperty "set;get socket option (Dealer)" (prop_set_get_socket_option Dealer)
    , testProperty "set;get socket option (Router)" (prop_set_get_socket_option Router)
    , testProperty "set;get socket option (Pull)"   (prop_set_get_socket_option Pull)
    , testProperty "set;get socket option (Push)"   (prop_set_get_socket_option Push)
    , testProperty "(un-)subscribe"                 (prop_subscribe Sub)
    , testCase     "last_enpoint"                   (last_endpoint)
    , testGroup    "connect disconnect"
        [ testProperty "" (prop_connect_disconnect x)
            | x <- [ (AnySocket Rep, AnySocket Req)
                   , (AnySocket Router, AnySocket Req)
                   , (AnySocket Pull, AnySocket Push)
                   ]
        ]
    , testGroup "0MQ Messages"
        [ testProperty "msg send == msg received (Req/Rep)"   (prop_send_receive Req Rep)
        , testProperty "msg send == msg received (Push/Pull)" (prop_send_receive Push Pull)
        , testProperty "msg send == msg received (Pair/Pair)" (prop_send_receive Pair Pair)
        -- , testProperty "publish/subscribe"                    (prop_pub_sub Pub Sub)
        -- (disabled due to LIBZMQ-270 [https://zeromq.jira.com/browse/LIBZMQ-270])
        ]
    ]

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
            Identity val        -> (== (rvalue val))  <$> (setIdentity val s >> identity s)
            Ipv4Only val        -> (== val)           <$> (setIpv4Only val s >> ipv4Only s)
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
    QM.assert r
  where
    ieq :: (Integral i, Integral k) => i -> k -> Bool
    ieq i k  = (fromIntegral i :: Int) == (fromIntegral k :: Int)

last_endpoint :: IO ()
last_endpoint = do
    let a = "tcp://127.0.0.1:43821"
    a' <- runZMQ $ do
        s <- socket Rep
        bind s a
        lastEndpoint s
    a @=? a'

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
        bind receiver "inproc://endpoint"
        x <- async $ receive receiver
        connect sender "inproc://endpoint"
        send sender [] msg
        liftIO $ wait x
    QM.assert (msg == msg')

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
    QM.assert (msg == msg')


prop_connect_disconnect :: (AnySocket, AnySocket) -> Property
prop_connect_disconnect (AnySocket t0, AnySocket t) = monadicIO $ run $
    runZMQ $ do
        s0 <- socket t0
        bind s0 "inproc://endpoint"
        s <- socket t
        connect s "inproc://endpoint"
        disconnect s "inproc://endpoint"

instance Arbitrary ByteString where
    arbitrary = CB.pack . filter (/= '\0') <$> arbitrary

data GetOpt =
    Events          Int
  | Filedesc        Fd
  | ReceiveMore     Bool
  deriving Show

data SetOpt =
    Affinity        Word64
  | Backlog         (Restricted (N0, Int32) Int)
  | Identity        (Restricted (N1, N254) ByteString)
  | Ipv4Only        Bool
  | Linger          (Restricted (Nneg1, Int32) Int)
  | MaxMessageSize  (Restricted (Nneg1, Int64) Int64)
  | McastHops       (Restricted (N1, Int32) Int)
  | Rate            (Restricted (N1, Int32) Int)
  | ReceiveBuf      (Restricted (N0, Int32) Int)
  | ReceiveHighWM   (Restricted (N0, Int32) Int)
  | ReceiveTimeout  (Restricted (Nneg1, Int32) Int)
  | ReconnectIVL    (Restricted (N0, Int32) Int)
  | ReconnectIVLMax (Restricted (N0, Int32) Int)
  | RecoveryIVL     (Restricted (N0, Int32) Int)
  | SendBuf         (Restricted (N0, Int32) Int)
  | SendHighWM      (Restricted (N0, Int32) Int)
  | SendTimeout     (Restricted (Nneg1, Int32) Int)
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

toR1 :: Int32 -> Restricted (N1, Int32) Int
toR1 = fromJust . toRestricted . fromIntegral

toR0 :: Int32 -> Restricted (N0, Int32) Int
toR0 = fromJust . toRestricted . fromIntegral

toRneg1 :: Int32 -> Restricted (Nneg1, Int32) Int
toRneg1 = fromJust . toRestricted . fromIntegral

toRneg1' :: Int64 -> Restricted (Nneg1, Int64) Int64
toRneg1' = fromJust . toRestricted . fromIntegral

data AnySocket where
    AnySocket :: SocketType a => a -> AnySocket

