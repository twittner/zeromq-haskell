{-# LANGUAGE FlexibleInstances #-}
module System.ZMQ3.Test.Properties where

import Control.Applicative
import Test.Framework (Test, testGroup)
import Test.Framework.Providers.QuickCheck2
import Test.QuickCheck
import Test.QuickCheck.Monadic

import Data.Int
import Data.Word
import Data.Restricted
import Data.Maybe (fromJust)
import Data.ByteString (ByteString)
import System.ZMQ3
import System.Posix.Types (Fd(..))
import qualified Data.ByteString as SB
import qualified Data.ByteString.Char8 as CB

tests :: [Test]
tests = [
    testGroup "0MQ Socket Properties" [
        testProperty "set/get socket option" (prop_set_get_socket_option Pair)
      , testProperty "(un-)subscribe"        (prop_subscribe Sub)
      ]
  , testGroup "0MQ Messages" [
        testProperty "msg send == msg received (Req/Rep)"   (prop_send_receive Req Rep)
      , testProperty "msg send == msg received (Push/Pull)" (prop_send_receive Push Pull)
      , testProperty "msg send == msg received (Pair/Pair)" (prop_send_receive Pair Pair)
      ]
  ]

prop_set_get_socket_option :: SType t => t -> SetOpt -> Property
prop_set_get_socket_option t opt = monadicIO $ do
    r <- run $
        withContext 1 $ \c ->
            withSocket c t $ \s ->
                case opt of
                    Identity val        -> (== (rvalue val)) <$> (setIdentity val s >> identity s)
                    Affinity val        -> (eq val)          <$> (setAffinity val s >> affinity s)
                    Backlog val         -> (eq (rvalue val)) <$> (setBacklog val s >> backlog s)
                    Linger val          -> (eq (rvalue val)) <$> (setLinger val s >> linger s)
                    Rate val            -> (eq (rvalue val)) <$> (setRate val s >> rate s)
                    ReceiveBuf val      -> (eq (rvalue val)) <$> (setReceiveBuffer val s >> receiveBuffer s)
                    ReconnectIVL val    -> (eq (rvalue val)) <$> (setReconnectInterval val s >> reconnectInterval s)
                    ReconnectIVLMax val -> (eq (rvalue val)) <$> (setReconnectIntervalMax val s >> reconnectIntervalMax s)
                    RecoveryIVL val     -> (eq (rvalue val)) <$> (setRecoveryInterval val s >> recoveryInterval s)
                    SendBuf val         -> (eq (rvalue val)) <$> (setSendBuffer val s >> sendBuffer s)
                    Ipv4Only val        -> (== val)          <$> (setIpv4Only val s >> ipv4Only s)
                    MaxMessageSize val  -> (eq val)          <$> (setMaxMessageSize val s >> maxMessageSize s)
                    McastHops val       -> (eq (rvalue val)) <$> (setMcastHops val s >> mcastHops s)
                    ReceiveHighWM val   -> (eq (rvalue val)) <$> (setReceiveHighWM val s >> receiveHighWM s)
                    ReceiveTimeout val  -> (eq (rvalue val)) <$> (setReceiveTimeout val s >> receiveTimeout s)
                    SendHighWM val      -> (eq (rvalue val)) <$> (setSendHighWM val s >> sendHighWM s)
                    SendTimeout val     -> (eq (rvalue val)) <$> (setSendTimeout val s >> sendTimeout s)
    assert r
  where
    eq :: (Integral i, Integral k) => i -> k -> Bool
    eq i k  = fromIntegral i == fromIntegral k

prop_subscribe :: (SubsType a, SType a) => a -> String -> Property
prop_subscribe t subs = monadicIO $ run $
    withContext 1 $ \c ->
        withSocket c t $ \s -> do
            subscribe s subs
            unsubscribe s subs

prop_send_receive :: (SType a, SType b) => a -> b -> ByteString -> Property
prop_send_receive a b msg = monadicIO $ do
    msg' <- run $ withContext 0 $ \c ->
                    withSocket c a $ \sender ->
                    withSocket c b $ \receiver -> do
                        bind receiver "inproc://endpoint"
                        connect sender "inproc://endpoint"
                        send sender [] msg
                        receive receiver
    assert (msg == msg')

instance Arbitrary ByteString where
    arbitrary = CB.pack <$> arbitrary

data GetOpt =
    Events          Int
  | ReceiveMore     Bool
  | Filedesc        Fd
  deriving Show

data SetOpt =
    Affinity        Word64
  | Backlog         (Restricted N0 Int32 Int)
  | Identity        (Restricted N1 N254 String)
  | Linger          (Restricted Nneg1 Int32 Int)
  | Rate            (Restricted N1 Int32 Int)
  | ReceiveBuf      (Restricted N0 Int32 Int)
  | ReconnectIVL    (Restricted N0 Int32 Int)
  | ReconnectIVLMax (Restricted N0 Int32 Int)
  | RecoveryIVL     (Restricted N0 Int32 Int)
  | SendBuf         (Restricted N0 Int32 Int)
  | Ipv4Only        Bool
  | MaxMessageSize  Int64
  | McastHops       (Restricted N1 Int32 Int)
  | ReceiveHighWM   (Restricted N0 Int32 Int)
  | ReceiveTimeout  (Restricted Nneg1 Int32 Int)
  | SendHighWM      (Restricted N0 Int32 Int)
  | SendTimeout     (Restricted Nneg1 Int32 Int)
  deriving Show

instance Arbitrary SetOpt where
    arbitrary = oneof [
        Identity . fromJust . restrict . show <$> arbitrary `suchThat` (\s -> SB.length s > 0 && SB.length s < 255)
      , Affinity              <$> (arbitrary :: Gen Word64)
      , Ipv4Only              <$> (arbitrary :: Gen Bool)
      , Backlog         . toR0 <$> (arbitrary :: Gen Int32) `suchThat` (>= 0)
      , Linger          . toRneg1 <$> (arbitrary :: Gen Int32) `suchThat` (>= -1)
      , Rate            . toR1 <$> (arbitrary :: Gen Int32) `suchThat` (> 0)
      , ReceiveBuf      . toR0 <$> (arbitrary :: Gen Int32) `suchThat` (>= 0)
      , ReconnectIVL    . toR0 <$> (arbitrary :: Gen Int32) `suchThat` (>= 0)
      , ReconnectIVLMax . toR0 <$> (arbitrary :: Gen Int32) `suchThat` (>= 0)
      , RecoveryIVL     . toR0 <$> (arbitrary :: Gen Int32) `suchThat` (>= 0)
      , SendBuf         . toR0 <$> (arbitrary :: Gen Int32) `suchThat` (>= 0)
      , MaxMessageSize  . fromIntegral <$> (arbitrary :: Gen Int32) `suchThat` (>= 0)
      , McastHops       . toR1 <$> (arbitrary :: Gen Int32) `suchThat` (> 0)
      , ReceiveHighWM   . toR0 <$> (arbitrary :: Gen Int32) `suchThat` (>= 0)
      , ReceiveTimeout  . toRneg1 <$> (arbitrary :: Gen Int32) `suchThat` (>= -1)
      , SendHighWM      . toR0 <$> (arbitrary :: Gen Int32) `suchThat` (>= 0)
      , SendTimeout     . toRneg1 <$> (arbitrary :: Gen Int32) `suchThat` (>= -1)
      ]

toR1 :: Int32 -> Restricted N1 Int32 Int
toR1 = fromJust . restrict . fromIntegral

toR0 :: Int32 -> Restricted N0 Int32 Int
toR0 = fromJust . restrict . fromIntegral

toRneg1 :: Int32 -> Restricted Nneg1 Int32 Int
toRneg1 = fromJust . restrict . fromIntegral
