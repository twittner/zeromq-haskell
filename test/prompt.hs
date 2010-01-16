import Control.Monad
import System.IO
import System.Exit
import System.Environment
import qualified System.ZMQ as ZMQ

main :: IO ()
main = do
    args <- getArgs
    when (length args /= 2) $ do
        hPutStrLn stderr "usage: prompt <address> <username>"
        exitFailure
    let addr = args !! 0
        name = args !! 1
    c <- ZMQ.init 1 1 False
    s <- ZMQ.socket c ZMQ.Pub
    ZMQ.connect s addr
    forever $ do
        line <- getLine
        ZMQ.send s (name ++ ": " ++ line) []

