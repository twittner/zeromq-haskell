import Test.Framework (defaultMain)
import qualified System.ZMQ3.Test.Properties as ZMQProperties
import qualified Data.Endpoint.Test.Properties as EPProperties

main :: IO ()
main = defaultMain $ ZMQProperties.tests ++ EPProperties.tests

