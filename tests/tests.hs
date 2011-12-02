import Test.Framework (defaultMain, testGroup)
import Test.Framework (Test)
import Test.Framework.Providers.HUnit

import qualified System.ZMQ as ZMQ

main :: IO ()
main = defaultMain tests

tests :: [Test]
tests = [
    testGroup "Init/Exit" [
        testCase "ZMQ Context" test_context
    ]
  , testGroup "Socket Creation" [
          testCase "Down" (test_socket ZMQ.Down)
        , testCase "Up"   (test_socket ZMQ.Up)
        , testCase "Push" (test_socket ZMQ.Push)
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
        , testCase "HighWM"          (test_option_get (ZMQ.HighWM undefined))
        , testCase "McastLoop"       (test_option_get (ZMQ.McastLoop undefined))
        , testCase "RecoveryIVLMsec" (test_option_get (ZMQ.RecoveryIVLMsec undefined))
        , testCase "Swap"            (test_option_get (ZMQ.Swap undefined))
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
        ZMQ.withSocket c ZMQ.XSub $ \s ->
            ZMQ.getOption s o >> return ()

