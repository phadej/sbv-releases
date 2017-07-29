-----------------------------------------------------------------------------
-- |
-- Module      :  TestSuite.Basics.TOut
-- Copyright   :  (c) Levent Erkok
-- License     :  BSD3
-- Maintainer  :  erkokl@gmail.com
-- Stability   :  experimental
--
-- Test the basic timeout mechanism
-----------------------------------------------------------------------------

module TestSuite.Basics.TOut(tests)  where

import Data.SBV.Examples.Puzzles.Euler185

import Utils.SBVTestFramework

-- Test suite
tests :: TestTree
tests =
  testGroup "Basics.timeout"
    [ goldenVsStringShow "timeout1" $ sat $ setTimeOut 1000 >> euler185
    ]
