import Control.Monad
import System.IO
import System.Exit
import System.Environment
import System.ZMQ4.Monadic
import qualified Data.ByteString as SB

main :: IO ()
main = do
    args <- getArgs
    when (length args /= 3) $ do
        hPutStrLn stderr usage
        exitFailure
    let bindTo = args !! 0
        size   = read $ args !! 1
        rounds = read $ args !! 2
    runZMQ $ do
        s <- socket Rep
        bind s bindTo
        loop s rounds size
  where
    loop s r sz = unless (r <= 0) $ do
        msg <- receive s
        when (SB.length msg /= sz) $
            error "message of incorrect size received"
        send s [] msg
        loop s (r - 1) sz

usage :: String
usage = "usage: local_lat <bind-to> <message-size> <roundtrip-count>"

