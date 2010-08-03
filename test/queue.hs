-- Demo application for a ZeroMQ 'queue' device
--
-- Compile using:
--
-- ghc --make -threaded queue.hs

import Control.Concurrent (forkOS, threadDelay)
import Control.Concurrent.MVar (MVar, newEmptyMVar, putMVar, takeMVar)

import Control.Monad (forever, forM_, replicateM, replicateM_)

import qualified Data.ByteString.Char8 as SB

import qualified System.ZMQ as ZMQ

main :: IO ()
main = do
    context <- ZMQ.init 1

    lock <- newEmptyMVar

    _ <- forkOS $ launchQueue context lock
    _ <- takeMVar lock

    forM_ [0..numWorkers] $ \i ->
        forkOS $ launchWorker context i

    locks <- replicateM numClients newEmptyMVar
    forM_ (zip [0..numClients] locks) $ \(i, lock') ->
        forkOS $ launchClient context i lock'

    -- Wait untill all clients signal completion
    forM_ locks takeMVar

    -- We can't clean up the context since our queue device is still running,
    -- and can't be killed...
    -- ZMQ.term context

 where
    numWorkers :: Int
    numWorkers = 5

    numClients :: Int
    numClients = 2 * numWorkers

    workersAddress :: String
    workersAddress = "inproc://workers"

    clientsAddress :: String
    clientsAddress = "tcp://127.0.0.1:5555"

    message :: SB.ByteString
    message = SB.replicate 10 '\0'

    delay :: Int
    delay = 1000000

    launchQueue :: ZMQ.Context -> MVar () -> IO ()
    launchQueue context lock = do
        workers <- ZMQ.socket context ZMQ.Xreq
        ZMQ.bind workers workersAddress

        clients <- ZMQ.socket context ZMQ.Xrep
        ZMQ.bind clients clientsAddress

        putMVar lock ()

        ZMQ.device ZMQ.Queue clients workers

        -- This isn't reached
        ZMQ.close workers
        ZMQ.close clients

    launchWorker :: ZMQ.Context -> Int -> IO ()
    launchWorker context i = do
        socket <- ZMQ.socket context ZMQ.Rep
        ZMQ.connect socket workersAddress

        forever $ do
            request <- ZMQ.receive socket []
            putStrLn $
                "Message received in worker " ++ show i ++ ": " ++
                SB.unpack request
            threadDelay delay -- Do some 'work'
            ZMQ.send socket message []
            putStrLn $ "Reply sent in worker " ++ show i

        -- This isn't reached
        ZMQ.close socket

    launchClient :: ZMQ.Context -> Int -> MVar () -> IO ()
    launchClient context i lock = do
        socket <- ZMQ.socket context ZMQ.Req
        ZMQ.connect socket clientsAddress

        putStrLn $ "Sending message in client " ++ show i
        ZMQ.send socket (SB.pack $ show i) []
        _ <- ZMQ.receive socket []
        putStrLn $ "Reply received in client " ++ show i

        ZMQ.close socket

        putMVar lock ()
