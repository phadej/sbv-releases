-----------------------------------------------------------------------------
-- |
-- Module    : TestSuite.Uninterpreted.Axioms
-- Author    : Levent Erkok
-- License   : BSD3
-- Maintainer: erkokl@gmail.com
-- Stability : experimental
--
-- Test suite for basic axioms and uninterpreted functions
-----------------------------------------------------------------------------

{-# LANGUAGE DeriveAnyClass     #-}
{-# LANGUAGE DeriveDataTypeable #-}

module TestSuite.Uninterpreted.Axioms(tests) where

import Utils.SBVTestFramework
import Data.Generics

tests :: TestTree
tests =
  testGroup "Uninterpreted.Axioms"
    [ testCase "unint-axioms" (assertIsThm p0) ]

-- Example provided by Thomas DuBuisson:
newtype Bitstring = Bitstring () deriving (Eq, Ord, Show, Read, Data, SymVal, HasKind)
type SBitstring = SBV Bitstring

a :: SBitstring -> SBool
a = uninterpret "a"

e :: SBitstring -> SBitstring -> SBitstring
e = uninterpret "e"

axE :: [String]
axE = [ "(assert (forall ((p Bitstring) (k Bitstring))"
      , "         (=> (and (a k) (a p)) (a (e k p)))))"
      ]

p0 :: Symbolic SBool
p0 = do
    p <- free "p" :: Symbolic SBitstring
    k <- free "k" :: Symbolic SBitstring
    addAxiom "axE" axE
    constrain $ a p
    constrain $ a k
    return $ a (e k p)
