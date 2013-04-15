module Test.Tools (quickBatch', checkBatch') where

import Control.Exception (catch, SomeException)
import Control.Monad
import System.Console.ANSI
import System.Exit
import Test.QuickCheck
import Test.QuickCheck.Checkers

quickBatch' :: TestBatch -> IO ()
quickBatch' = checkBatch' (stdArgs { maxSuccess = 500 })

checkBatch' :: Args -> TestBatch -> IO ()
checkBatch' args (name, tsts) = do
    writeLn Cyan name
    forM_ tsts $ \(s, p) -> do
        write White ("    " ++ s ++ ": ")
        r <- quickCheckWithResult (args { chatty = False}) p
             `catch`
             ((\e -> write Red (show e) >> exitFailure) :: SomeException -> IO a)
        case r of
            Success _ _ m           -> write Green m
            GaveUp  _ _ m           -> write Magenta m >> exitFailure
            Failure _ _ _ _ _ _ _ m -> write Red m     >> exitFailure
            NoExpectedFailure _ _ m -> write Red m     >> exitFailure

write, writeLn :: Color -> String -> IO ()
write   c = withColour c . putStr
writeLn c = withColour c . putStrLn

withColour :: Color -> IO () -> IO ()
withColour c a = do
    setSGR [Reset, SetColor Foreground Vivid c]
    a
    setSGR [Reset]
