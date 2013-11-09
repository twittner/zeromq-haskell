{-# LANGUAGE OverloadedStrings #-}
import Control.Concurrent
import Control.Monad
import System.IO
import System.Exit
import System.Environment
import Data.Time.Clock
import System.ZMQ4.Monadic
import qualified Data.ByteString as SB
import Text.Printf

main :: IO ()
main = do
    args <- getArgs
    when (length args /= 3) $ do
        hPutStrLn stderr usage
        exitFailure
    let bindTo = args !! 0
        size   = read $ args !! 1
        count  = read $ args !! 2
    runZMQ $ do
        s <- socket Sub
        subscribe s ""
        bind s bindTo
        receive' s size
        start <- liftIO $ getCurrentTime
        loop s count size
        end <- liftIO $ getCurrentTime
        liftIO $ printStat start end size count
  where
    receive' s sz = do
        msg <- receive s
        when (SB.length msg /= sz) $
            error "message of incorrect size received"

    loop s c sz = unless (c < 0) $ do
        receive' s sz
        loop s (c - 1) sz

    printStat :: UTCTime -> UTCTime -> Int -> Int -> IO ()
    printStat start end size count = do
        let elapsed = fromRational . toRational $ diffUTCTime end start :: Double
            through = fromIntegral count / elapsed
            mbits   = (through * fromIntegral size * 8) / 1000000
        printf "message size: %d [B]\n" size
        printf "message count: %d\n" count
        printf "mean throughput: %.3f [msg/s]\n" through
        printf "mean throughput: %.3f [Mb/s]\n" mbits

usage :: String
usage = "usage: local_thr <bind-to> <message-size> <message-count>"

