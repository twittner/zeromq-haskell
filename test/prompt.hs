{-# LANGUAGE OverloadedStrings #-}
import Control.Applicative
import Control.Monad
import System.IO
import System.Exit
import System.Environment
import qualified System.ZMQ as ZMQ
import qualified Data.ByteString.UTF8 as SB
import qualified Data.ByteString.Char8 as SB

main :: IO ()
main = do
    args <- getArgs
    when (length args /= 2) $ do
        hPutStrLn stderr "usage: prompt <address> <username>"
        exitFailure
    let addr = args !! 0
        name = SB.append (SB.fromString $ args !! 1) ": "
    ZMQ.with 1 $ \c -> do
      s <- ZMQ.socket c ZMQ.Pub
      ZMQ.bind s addr
      forever $ do
        line <- SB.fromString <$> getLine
        ZMQ.send s (SB.append name line) []

