{-# LANGUAGE CPP #-}
import Test.Framework (defaultMain)
import qualified System.ZMQ.Test.Properties as Properties

main :: IO ()
main = defaultMain Properties.tests

