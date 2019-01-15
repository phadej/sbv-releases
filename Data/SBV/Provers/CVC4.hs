-----------------------------------------------------------------------------
-- |
-- Module    : Data.SBV.Provers.CVC4
-- Author    : Levent Erkok
-- License   : BSD3
-- Maintainer: erkokl@gmail.com
-- Stability : experimental
--
-- The connection to the CVC4 SMT solver
-----------------------------------------------------------------------------

{-# LANGUAGE ScopedTypeVariables #-}

module Data.SBV.Provers.CVC4(cvc4) where

import Data.Char (isSpace)

import Data.SBV.Core.Data
import Data.SBV.SMT.SMT

-- | The description of the CVC4 SMT solver
-- The default executable is @\"cvc4\"@, which must be in your path. You can use the @SBV_CVC4@ environment variable to point to the executable on your system.
-- The default options are @\"--lang smt\"@. You can use the @SBV_CVC4_OPTIONS@ environment variable to override the options.
cvc4 :: SMTSolver
cvc4 = SMTSolver {
           name         = CVC4
         , executable   = "cvc4"
         , preprocess   = clean
         , options      = const ["--lang", "smt", "--incremental", "--interactive", "--no-interactive-prompt"]
         , engine       = standardEngine "SBV_CVC4" "SBV_CVC4_OPTIONS"
         , capabilities = SolverCapabilities {
                                supportsQuantifiers        = True
                              , supportsUninterpretedSorts = True
                              , supportsUnboundedInts      = True
                              , supportsReals              = True  -- Not quite the same capability as Z3; but works more or less..
                              , supportsApproxReals        = False
                              , supportsIEEE754            = False
                              , supportsOptimization       = False
                              , supportsPseudoBooleans     = False
                              , supportsCustomQueries      = True
                              , supportsGlobalDecls        = True
                              , supportsFlattenedSequences = Nothing
                              }
         }
  where -- CVC4 wants all input on one line
        clean = map simpleSpace . noComment

        noComment ""       = ""
        noComment (';':cs) = noComment $ dropWhile (/= '\n') cs
        noComment (c:cs)   = c : noComment cs

        simpleSpace c
          | isSpace c = ' '
          | True      = c
