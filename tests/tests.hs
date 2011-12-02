import Test.Framework (defaultMain, testGroup)
import Test.Framework (Test)
import Test.Framework.Providers.HUnit

import qualified System.ZMQ as ZMQ

main :: IO ()
main = defaultMain tests

tests :: [Test]
tests = [
    testGroup "Misc" [
          testCase "ZMQ Context" test_context
    ]
  , testGroup "Socket Creation" [
          testCase "Push" (test_socket ZMQ.Push)
        , testCase "Pull" (test_socket ZMQ.Pull)
        , testCase "XRep" (test_socket ZMQ.XRep)
        , testCase "XReq" (test_socket ZMQ.XReq)
        , testCase "Rep"  (test_socket ZMQ.Rep)
        , testCase "Req"  (test_socket ZMQ.Req)
        , testCase "XPub" (test_socket ZMQ.XSub)
        , testCase "XSub" (test_socket ZMQ.XPub)
        , testCase "Sub"  (test_socket ZMQ.Sub)
        , testCase "Pub"  (test_socket ZMQ.Pub)
        , testCase "Pair" (test_socket ZMQ.Pair)
--ifdef ZMQ2
        , testCase "Down" (test_socket ZMQ.Down)
        , testCase "Up"   (test_socket ZMQ.Up)
--endif
    ]
  , testGroup "Socket Option (get)" [
          testCase "Affinity"        (test_option_get (ZMQ.Affinity undefined))
        , testCase "Backlog"         (test_option_get (ZMQ.Backlog undefined))
        , testCase "Events"          (test_option_get (ZMQ.Events undefined))
        , testCase "FD"              (test_option_get (ZMQ.FD undefined))
        , testCase "Identity"        (test_option_get (ZMQ.Identity undefined))
        , testCase "Linger"          (test_option_get (ZMQ.Linger undefined))
        , testCase "Rate"            (test_option_get (ZMQ.Rate undefined))
        , testCase "ReceiveBuf"      (test_option_get (ZMQ.ReceiveBuf undefined))
        , testCase "ReceiveMore"     (test_option_get (ZMQ.ReceiveMore undefined))
        , testCase "ReconnectIVL"    (test_option_get (ZMQ.ReconnectIVL undefined))
        , testCase "ReconnectIVLMax" (test_option_get (ZMQ.ReconnectIVLMax undefined))
        , testCase "ReconnectIVL"    (test_option_get (ZMQ.RecoveryIVL undefined))
        , testCase "SendBuf"         (test_option_get (ZMQ.SendBuf undefined))
--ifdef ZMQ2
        , testCase "HighWM"          (test_option_get (ZMQ.HighWM undefined))
        , testCase "McastLoop"       (test_option_get (ZMQ.McastLoop undefined))
        , testCase "RecoveryIVLMsec" (test_option_get (ZMQ.RecoveryIVLMsec undefined))
        , testCase "Swap"            (test_option_get (ZMQ.Swap undefined))
--endif
    ]
  , testGroup "Socket Option (set)" [
          testCase "Affinity"        (test_option_set (ZMQ.Affinity 0))
        , testCase "Backlog"         (test_option_set (ZMQ.Backlog 100))
        , testCase "Events"          (test_option_set (ZMQ.Events undefined))
        , testCase "FD"              (test_option_set (ZMQ.FD undefined))
        , testCase "Identity"        (test_option_set (ZMQ.Identity "id"))
        , testCase "Linger"          (test_option_set (ZMQ.Linger (-1)))
        , testCase "Rate"            (test_option_set (ZMQ.Rate 100))
        , testCase "ReceiveBuf"      (test_option_set (ZMQ.ReceiveBuf 0))
        , testCase "ReceiveMore"     (test_option_set (ZMQ.ReceiveMore undefined))
        , testCase "ReconnectIVL"    (test_option_set (ZMQ.ReconnectIVL 100))
        , testCase "ReconnectIVLMax" (test_option_set (ZMQ.ReconnectIVLMax 0))
        , testCase "ReconnectIVL"    (test_option_set (ZMQ.RecoveryIVL 100))
        , testCase "SendBuf"         (test_option_set (ZMQ.SendBuf 0))
--ifdef ZMQ2
        , testCase "HighWM"          (test_option_set (ZMQ.HighWM 0))
        , testCase "McastLoop"       (test_option_set (ZMQ.McastLoop True))
        , testCase "RecoveryIVLMsec" (test_option_set (ZMQ.RecoveryIVLMsec (-1)))
        , testCase "Swap"            (test_option_set (ZMQ.Swap 0))
--endif
    ]
  , testGroup "Pub/Sub" [
          testCase "Subscribe Sub"    (test_subscribe ZMQ.Sub)
        , testCase "Subscribe XSub"   (test_subscribe ZMQ.XSub)
        , testCase "Unsubscribe Sub"  (test_unsubscribe ZMQ.Sub)
        , testCase "Unsubscribe XSub" (test_unsubscribe ZMQ.XSub)
    ]
  ]

test_context :: IO ()
test_context = do
    c1 <- ZMQ.init 1
    c2 <- ZMQ.init 3
    ZMQ.term c1
    ZMQ.term c2

test_socket :: ZMQ.SType a => a -> IO ()
test_socket ty =
    ZMQ.withContext 1 $ \c ->
        ZMQ.socket c ty >>= ZMQ.close

test_option_get :: ZMQ.SocketOption -> IO ()
test_option_get o =
    ZMQ.withContext 1 $ \c ->
    ZMQ.withSocket c ZMQ.Sub $ \s ->
        ZMQ.getOption s o >> return ()

test_option_set :: ZMQ.SocketOption -> IO ()
test_option_set o =
    ZMQ.withContext 1 $ \c ->
    ZMQ.withSocket c ZMQ.Sub $ \s ->
        ZMQ.setOption s o

test_subscribe :: (ZMQ.SubsType a, ZMQ.SType a) => a -> IO ()
test_subscribe ty =
    ZMQ.withContext 1 $ \c ->
        ZMQ.withSocket c ty $ \s ->
            ZMQ.subscribe s ""

test_unsubscribe :: (ZMQ.SubsType a, ZMQ.SType a) => a -> IO ()
test_unsubscribe ty =
    ZMQ.withContext 1 $ \c ->
        ZMQ.withSocket c ty $ \s ->
            ZMQ.unsubscribe s ""
