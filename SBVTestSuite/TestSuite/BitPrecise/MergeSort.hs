-----------------------------------------------------------------------------
-- |
-- Module      :  TestSuite.BitPrecise.MergeSort
-- Copyright   :  (c) Levent Erkok
-- License     :  BSD3
-- Maintainer  :  erkokl@gmail.com
-- Stability   :  experimental
--
-- Test suite for Data.SBV.Examples.BitPrecise.MergeSort
-----------------------------------------------------------------------------

module TestSuite.BitPrecise.MergeSort(tests) where

import Data.SBV.Internals
import Data.SBV.Examples.BitPrecise.MergeSort

import Utils.SBVTestFramework

-- Test suite
tests :: TestTree
tests = testGroup "BitPrecise.MergeSort" [
   goldenVsStringShow "merge" mergeC
 ]
 where mergeC = compileToC' "merge" $ do
                   cgSetDriverValues [10, 6, 4, 82, 71]
                   xs <- cgInputArr 5 "xs"
                   cgOutputArr "ys" (mergeSort xs)
