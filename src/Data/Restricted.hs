{-# LANGUAGE EmptyDataDecls         #-}
{-# LANGUAGE MultiParamTypeClasses  #-}
{-# LANGUAGE FlexibleInstances      #-}
{-# LANGUAGE UndecidableInstances   #-}
{-# LANGUAGE TypeSynonymInstances   #-}
{-# LANGUAGE OverloadedStrings      #-}

-- |
-- Module      : Data.Restricted
-- Copyright   : (c) 2011-2013 Toralf Wittner
-- License     : MIT
-- Maintainer  : Toralf Wittner <tw@dtex.org>
-- Stability   : experimental
-- Portability : non-portable
--
-- Type-level restricted data.
-- This module allows for type declarations which embed certain restrictions,
-- such as value bounds. E.g. @Restricted N0 N1 Int@ denotes an 'Int' which can
-- only have values [0 .. 1]. When creating such a value, the constructor functions
-- 'restrict' or 'toRestricted' ensure that the restrictions are obeyed. Code
-- that consumes restricted types does not need to check the constraints.
--
-- /N.B./ This module is more or less tailored to be used within 'System.ZMQ3'.
-- Therefore the provided type level restrictions are limited.
module Data.Restricted (

    Restricted
  , Restriction (..)
  , rvalue

  , Nneg1
  , N1
  , N0
  , N254
  , Inf
  , Div4
  , Div5

) where

import Data.Int
import Data.ByteString (ByteString)
import qualified Data.ByteString as B

-- | Type level restriction.
newtype Restricted r v = Restricted v deriving Show

-- | A uniform way to restrict values.
class Restriction r v where

    -- | Create a restricted value. Returns 'Nothing' if
    -- the given value does not satisfy all restrictions.
    toRestricted :: v -> Maybe (Restricted r v)

    -- | Create a restricted value. If the given value
    -- does not satisfy the restrictions, a modified
    -- variant is used instead, e.g. if an integer is
    -- larger than the upper bound, the upper bound
    -- value is used.
    restrict :: v -> Restricted r v

-- | Get the actual value.
rvalue :: Restricted r v -> v
rvalue (Restricted v) = v

-- | type level -1
data Nneg1

-- | type-level   0
data N0

-- | type-level   1
data N1

-- | type-level 254
data N254

-- | type-level infinity
data Inf

-- | divisable by 4
data Div4

-- | divisable by 5
data Div5

instance Show Nneg1 where show _ = "Nneg1"
instance Show N0    where show _ = "N0"
instance Show N1    where show _ = "N1"
instance Show N254  where show _ = "N254"
instance Show Inf   where show _ = "Inf"
instance Show Div4  where show _ = "Div4"
instance Show Div5  where show _ = "Div5"

-- Natural numbers

instance (Integral a) => Restriction (N0, Inf) a where
    toRestricted = toIntRLB 0
    restrict     = intRLB   0

instance (Integral a) => Restriction (N0, Int32) a where
    toRestricted = toIntR 0 (maxBound :: Int32)
    restrict     = intR   0 (maxBound :: Int32)

instance (Integral a) => Restriction (N0, Int64) a where
    toRestricted = toIntR 0 (maxBound :: Int64)
    restrict     = intR   0 (maxBound :: Int64)

-- Positive natural numbers

instance (Integral a) => Restriction (N1, Inf) a where
    toRestricted = toIntRLB 1
    restrict     = intRLB   1

instance (Integral a) => Restriction (N1, Int32) a where
    toRestricted = toIntR 1 (maxBound :: Int32)
    restrict     = intR   1 (maxBound :: Int32)

instance (Integral a) => Restriction (N1, Int64) a where
    toRestricted = toIntR 1 (maxBound :: Int64)
    restrict     = intR   1 (maxBound :: Int64)

-- From -1 ranges

instance (Integral a) => Restriction (Nneg1, Inf) a where
    toRestricted = toIntRLB (-1)
    restrict     = intRLB   (-1)

instance (Integral a) => Restriction (Nneg1, Int32) a where
    toRestricted = toIntR (-1) (maxBound :: Int32)
    restrict     = intR   (-1) (maxBound :: Int32)

instance (Integral a) => Restriction (Nneg1, Int64) a where
    toRestricted = toIntR (-1) (maxBound :: Int64)
    restrict     = intR   (-1) (maxBound :: Int64)

-- Other ranges

instance Restriction (N1, N254) String where
    toRestricted s | check (1, 254) (length s) = Just $ Restricted s
                   | otherwise                 = Nothing

    restrict s | length s < 1 = Restricted " "
               | otherwise    = Restricted (take 254 s)

instance Restriction (N1, N254) ByteString where
    toRestricted s | check (1, 254) (B.length s) = Just $ Restricted s
                   | otherwise                   = Nothing

    restrict s | B.length s < 1 = Restricted (B.singleton 0x20)
               | otherwise      = Restricted (B.take 254 s)

-- Other constraints

instance Restriction Div4 ByteString where
    toRestricted s | B.length s `mod` 4 == 0 = Just $ Restricted s
                   | otherwise               = Nothing

    restrict = fitByRem 4

instance Restriction Div5 ByteString where
    toRestricted s | B.length s `mod` 5 == 0 = Just $ Restricted s
                   | otherwise               = Nothing

    restrict = fitByRem 5

-- Helpers

toIntR :: (Integral i, Integral j) => i -> j -> i -> Maybe (Restricted (a, b) i)
toIntR lb ub i | check (lb, fromIntegral ub) i = Just $ Restricted i
               | otherwise                     = Nothing

intR :: (Integral i, Integral j) => i -> j -> i -> Restricted (a, b) i
intR lb ub = Restricted . lbfit lb . ubfit (fromIntegral ub)

toIntRLB :: Integral i => i -> i -> Maybe (Restricted (a, b) i)
toIntRLB lb i | lbcheck lb i = Just $ Restricted i
              | otherwise    = Nothing

intRLB :: Integral i => i -> i -> Restricted (a, b) i
intRLB lb = Restricted . lbfit lb

-- Bounds checks

lbcheck :: Ord a => a -> a -> Bool
lbcheck lb a = a >= lb

ubcheck :: Ord a => a -> a -> Bool
ubcheck ub a = a <= ub

check :: Ord a => (a, a) -> a -> Bool
check (lb, ub) a = lbcheck lb a && ubcheck ub a

-- Fit

lbfit :: Integral a => a -> a -> a
lbfit lb a | a >= lb   = a
           | otherwise = lb

ubfit :: Integral a => a -> a -> a
ubfit ub a | a <= ub   = a
           | otherwise = ub

fitByRem :: Int -> ByteString -> Restricted r ByteString
fitByRem r s =
    let len = B.length s
        x   = len `mod` r
    in if x == 0
        then Restricted s
        else Restricted (B.take (len - x) s)

