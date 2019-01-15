-----------------------------------------------------------------------------
-- |
-- Module    : TestSuite.Puzzles.Temperature
-- Author    : Levent Erkok
-- License   : BSD3
-- Maintainer: erkokl@gmail.com
-- Stability : experimental
--
-- Test suite for Examples.Puzzles.Temperature
-----------------------------------------------------------------------------

module TestSuite.Puzzles.Temperature(tests) where

import Utils.SBVTestFramework

import Data.List (sort)
import qualified Data.Map as M

-- Test suite
tests :: TestTree
tests =
  testGroup "Puzzles.Temperature"
    [ goldenVsStringShow "temperature" result
    ]
    where result = (sort . concatMap M.toList . getModelDictionaries) `fmap` allSat (revOf `fmap` exists_)

type Temp = SInteger

-- convert celcius to fahrenheit, rounding up/down properly
-- we have to be careful here to make sure rounding is done properly..
d2f :: Temp -> Temp
d2f d = 32 + ite (fr .>= 5) (1+fi) fi
  where (fi, fr) = (18 * d) `sQuotRem` 10

-- puzzle: What 2 digit fahrenheit/celcius values are reverses of each other?
revOf :: Temp -> SBool
revOf c = swap (digits c) .== digits (d2f c)
  where digits x = x `sQuotRem` 10
        swap (a, b) = (b, a)
