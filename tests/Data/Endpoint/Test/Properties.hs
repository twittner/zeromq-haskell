module Data.Endpoint.Test.Properties where

import Control.Applicative
import Test.Framework (Test, testGroup)
import Test.Framework.Providers.QuickCheck2
import Test.QuickCheck

import Data.Char
import Data.IP
import Data.Word
import System.ZMQ3

tests :: [Test]
tests = [
    testGroup "Data.Endpoint tests" [
        testProperty "read . show == id" prop_show_read
    ]
  ]

prop_show_read :: Endpoint -> Bool
prop_show_read ep = (ep ==) . read . show $ ep

instance Arbitrary Endpoint where
    arbitrary = oneof [
        InProc <$> max_size 32 str
      , IPC    <$> max_size 32 str
      , TCP    <$> arbitrary
--      , PGM    <$> arbitrary
--      , EPGM   <$> arbitrary
      ]

instance Arbitrary TcpAddress where
    arbitrary = oneof [
        TAddr  <$> arbitrary       <*> arbitrary
      , TIface <$> max_size 32 str <*> arbitrary
      ]

instance Arbitrary PgmAddress where
    arbitrary = oneof [
        PAddr  <$> arbitrary       <*> arbitrary <*> arbitrary
      , PIface <$> max_size 32 str <*> arbitrary <*> arbitrary
      ]

instance Arbitrary IP where
    arbitrary = oneof [
        IPv4 . toIPv4 <$> ip4AddrList
      , IPv6 . toIPv6 <$> ip6AddrList
      , IPv6 . read   <$> ip6AddrSamples
      ]

ip4AddrList :: Gen [Int]
ip4AddrList = map fromIntegral <$> vectorOf 4 (arbitrary :: Gen Word16)

ip6AddrList :: Gen [Int]
ip6AddrList = map fromIntegral <$> vectorOf 8 (arbitrary :: Gen Word16)

ip6AddrSamples :: Gen String
ip6AddrSamples = elements [
    "ABCD:EF01:2345:6789:ABCD:EF01:2345:6789"
  , "2001:DB8:0:0:8:800:200C:417A"
  , "2001:DB8:0:0:8:800:200C:417A"
  , "FF01:0:0:0:0:0:0:101"
  , "0:0:0:0:0:0:0:1"
  , "0:0:0:0:0:0:0:0"
  , "2001:DB8::8:800:200C:417A"
  , "FF01::101"
  , "::1"
  , "::"
  , "0:0:0:0:0:0:13.1.68.3"
  , "0:0:0:0:0:FFFF:129.144.52.38"
  , "::13.1.68.3"
  , "::FFFF:129.144.52.38"
  , "2001:0DB8:0000:CD30:0000:0000:0000:0000/60"
  , "2001:0DB8::CD30:0:0:0:0/60"
  , "2001:0DB8:0:CD30::/60"
  , "2001:0DB8:0:CD30:123:4567:89AB:CDEF/60"
  ]

str :: Gen String
str = arbitrary `suchThat` (\s -> (not . null $ s) && all isAlpha s)

max_size :: Int -> Gen a -> Gen a
max_size limit g = sized $ \n -> resize (n `mod` limit) g
