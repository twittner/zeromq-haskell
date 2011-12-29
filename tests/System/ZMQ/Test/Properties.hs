module System.ZMQ.Test.Properties where

import Control.Applicative
import Test.Framework (Test, testGroup)
import Test.Framework.Providers.QuickCheck2
import Test.QuickCheck
import Test.QuickCheck.Monadic

import Data.Int
import Data.Word
import Data.ByteString (ByteString)
import qualified System.ZMQ as ZMQ
import qualified Data.ByteString as SB
import qualified Data.ByteString.Char8 as CB

tests :: [Test]
tests = [
    testGroup "0MQ Socket Properties" [
        testProperty "get socket option (Push)" (prop_get_socket_option ZMQ.Push)
      , testProperty "get socket option (Pull)" (prop_get_socket_option ZMQ.Pull)
      , testProperty "get socket option (XRep)" (prop_get_socket_option ZMQ.XRep)
      , testProperty "get socket option (XReq)" (prop_get_socket_option ZMQ.XReq)
      , testProperty "get socket option (Rep)"  (prop_get_socket_option ZMQ.Rep)
      , testProperty "get socket option (Req)"  (prop_get_socket_option ZMQ.Req)
      , testProperty "get socket option (Sub)"  (prop_get_socket_option ZMQ.Sub)
      , testProperty "get socket option (Pub)"  (prop_get_socket_option ZMQ.Pub)
      , testProperty "get socket option (Pair)" (prop_get_socket_option ZMQ.Pair)
      , testProperty "get socket option (Down)" (prop_get_socket_option ZMQ.Down)
      , testProperty "get socket option (Up)"   (prop_get_socket_option ZMQ.Up)

      , testProperty "set/get socket option (Push)" (prop_set_get_socket_option ZMQ.Push)
      , testProperty "set/get socket option (Pull)" (prop_set_get_socket_option ZMQ.Pull)
      , testProperty "set/get socket option (XRep)" (prop_set_get_socket_option ZMQ.XRep)
      , testProperty "set/get socket option (XReq)" (prop_set_get_socket_option ZMQ.XReq)
      , testProperty "set/get socket option (Rep)"  (prop_set_get_socket_option ZMQ.Rep)
      , testProperty "set/get socket option (Req)"  (prop_set_get_socket_option ZMQ.Req)
      , testProperty "set/get socket option (Sub)"  (prop_set_get_socket_option ZMQ.Sub)
      , testProperty "set/get socket option (Pub)"  (prop_set_get_socket_option ZMQ.Pub)
      , testProperty "set/get socket option (Pair)" (prop_set_get_socket_option ZMQ.Pair)
      , testProperty "set/get socket option (Down)" (prop_set_get_socket_option ZMQ.Down)
      , testProperty "set/get socket option (Up)"   (prop_set_get_socket_option ZMQ.Up)

      , testProperty "(un-)subscribe" (prop_subscribe ZMQ.Sub)
      ]
  , testGroup "0MQ Messages" [
        testProperty "msg send == msg received (Req/Rep)"   (prop_send_receive ZMQ.Req ZMQ.Rep)
      , testProperty "msg send == msg received (Push/Pull)" (prop_send_receive ZMQ.Push ZMQ.Pull)
      , testProperty "msg send == msg received (Pair/Pair)" (prop_send_receive ZMQ.Pair ZMQ.Pair)
      , testProperty "publish/subscribe (Pub/Sub)"          (prop_pub_sub ZMQ.Pub ZMQ.Sub)
      ]
  ]

prop_get_socket_option :: ZMQ.SType a => a -> Property
prop_get_socket_option t = forAll readOnlyOptions canGetOption
  where
    canGetOption opt = monadicIO $ run $
        ZMQ.withContext 1 $ \c ->
            ZMQ.withSocket c t $ \s -> ZMQ.getOption s opt

prop_set_get_socket_option :: ZMQ.SType a => a -> ZMQ.SocketOption -> Property
prop_set_get_socket_option t opt = monadicIO $ do
    o <- run $ ZMQ.withContext 1 $ \c ->
                    ZMQ.withSocket c t $ \s -> do
                        ZMQ.setOption s opt
                        ZMQ.getOption s opt
    assert (opt == o)

prop_subscribe :: (ZMQ.SubsType a, ZMQ.SType a) => a -> String -> Property
prop_subscribe t subs = monadicIO $ run $
    ZMQ.withContext 1 $ \c ->
        ZMQ.withSocket c t $ \s -> do
            ZMQ.subscribe s subs
            ZMQ.unsubscribe s subs

prop_send_receive :: (ZMQ.SType a, ZMQ.SType b) => a -> b -> ByteString -> Property
prop_send_receive a b msg = monadicIO $ do
    msg' <- run $ ZMQ.withContext 0 $ \c ->
                    ZMQ.withSocket c a $ \sender ->
                    ZMQ.withSocket c b $ \receiver -> do
                        ZMQ.bind receiver "inproc://endpoint"
                        ZMQ.connect sender "inproc://endpoint"
                        ZMQ.send sender msg []
                        ZMQ.receive receiver []
    assert (msg == msg')

prop_pub_sub :: (ZMQ.SType a, ZMQ.SubsType b, ZMQ.SType b) => a -> b -> ByteString -> Property
prop_pub_sub a b msg = monadicIO $ do
    msg' <- run $ ZMQ.withContext 0 $ \c ->
                    ZMQ.withSocket c a $ \pub ->
                    ZMQ.withSocket c b $ \sub -> do
                        ZMQ.subscribe sub ""
                        ZMQ.bind sub "inproc://endpoint"
                        ZMQ.connect pub "inproc://endpoint"
                        ZMQ.send pub msg []
                        ZMQ.receive sub []
    assert (msg == msg')
instance Arbitrary ZMQ.SocketOption where
    arbitrary = oneof [
        ZMQ.Affinity . fromIntegral        <$> (arbitrary :: Gen Word64)
      , ZMQ.Backlog . fromIntegral         <$> (arbitrary :: Gen Int32)
      , ZMQ.Linger . fromIntegral          <$> (arbitrary :: Gen Int32)
      , ZMQ.Rate . fromIntegral            <$> (arbitrary :: Gen Word32)
      , ZMQ.ReceiveBuf . fromIntegral      <$> (arbitrary :: Gen Word64)
      , ZMQ.ReconnectIVL . fromIntegral    <$> (arbitrary :: Gen Int32)  `suchThat` (>= 0)
      , ZMQ.ReconnectIVLMax . fromIntegral <$> (arbitrary :: Gen Int32)  `suchThat` (>= 0)
      , ZMQ.RecoveryIVL . fromIntegral     <$> (arbitrary :: Gen Word32)
      , ZMQ.RecoveryIVLMsec .fromIntegral  <$> (arbitrary :: Gen Int32)  `suchThat` (>= 0)
      , ZMQ.SendBuf . fromIntegral         <$> (arbitrary :: Gen Word64)
      , ZMQ.HighWM . fromIntegral          <$> (arbitrary :: Gen Word64)
      , ZMQ.McastLoop                      <$> (arbitrary :: Gen Bool)
      , ZMQ.Swap . fromIntegral            <$> (arbitrary :: Gen Int64)  `suchThat` (>= 0)
      , ZMQ.Identity . show                <$> arbitrary `suchThat` (\s -> SB.length s > 0 && SB.length s < 255)
      ]

instance Arbitrary ByteString where
    arbitrary = CB.pack <$> arbitrary

readOnlyOptions :: Gen ZMQ.SocketOption
readOnlyOptions = elements [ZMQ.FD undefined, ZMQ.ReceiveMore undefined, ZMQ.Events undefined]

