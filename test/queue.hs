-- Demo application for a ZeroMQ 'queue' device
--
-- Compile using:
--
-- ghc --make -threaded queue.hs

import Control.Concurrent (forkIO, threadDelay)
import Control.Concurrent.MVar (MVar, newEmptyMVar, putMVar, takeMVar)
import Control.Monad (forever, forM_, replicateM, replicateM_)
import qualified Data.ByteString.Char8 as SB
import qualified System.ZMQ as ZMQ

main :: IO ()
main = ZMQ.withContext 1 $ \context -> do
    lock <- newEmptyMVar
    _    <- forkIO $ launchQueue context lock
    _    <- takeMVar lock

    forM_ [0..numWorkers] $ \i ->
        forkIO $ launchWorker context i

    locks <- replicateM numClients newEmptyMVar
    forM_ (zip [0..numClients] locks) $ \(i, lock') ->
        forkIO $ launchClient context i lock'

    -- Wait untill all clients signal completion
    forM_ locks takeMVar

    -- our queue device is still running, and can't be killed...

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
    launchQueue context lock =
        ZMQ.withSocket context ZMQ.Xreq $ \workers ->
        ZMQ.withSocket context ZMQ.Xrep $ \clients -> do
            ZMQ.bind workers workersAddress
            ZMQ.bind clients clientsAddress
            putMVar lock ()
            ZMQ.device ZMQ.Queue clients workers

    launchWorker :: ZMQ.Context -> Int -> IO ()
    launchWorker context i =
        ZMQ.withSocket context ZMQ.Rep $ \socket -> do
            ZMQ.connect socket workersAddress
            forever $ do
                request <- ZMQ.receive socket []
                putStrLn $
                    "Message received in worker " ++ show i ++ ": " ++
                    SB.unpack request
                threadDelay delay -- Do some 'work'
                ZMQ.send socket message []
                putStrLn $ "Reply sent in worker " ++ show i

    launchClient :: ZMQ.Context -> Int -> MVar () -> IO ()
    launchClient context i lock = do
        ZMQ.withSocket context ZMQ.Req $ \socket -> do
            ZMQ.connect socket clientsAddress
            putStrLn $ "Sending message in client " ++ show i
            ZMQ.send socket (SB.pack $ show i) []
            _ <- ZMQ.receive socket []
            putStrLn $ "Reply received in client " ++ show i
        putMVar lock ()
