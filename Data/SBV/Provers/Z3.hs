-----------------------------------------------------------------------------
-- |
-- Module    : Data.SBV.Provers.Z3
-- Author    : Levent Erkok
-- License   : BSD3
-- Maintainer: erkokl@gmail.com
-- Stability : experimental
--
-- The connection to the MathSAT SMT solver
-----------------------------------------------------------------------------

{-# LANGUAGE ScopedTypeVariables #-}

module Data.SBV.Provers.Z3(z3) where

import Data.SBV.Core.Data
import Data.SBV.SMT.SMT

-- | The description of the Z3 SMT solver.
-- The default executable is @\"z3\"@, which must be in your path. You can use the @SBV_Z3@ environment variable to point to the executable on your system.
-- The default options are @\"-nw -in -smt2\"@. You can use the @SBV_Z3_OPTIONS@ environment variable to override the options.
z3 :: SMTSolver
z3 = SMTSolver {
           name         = Z3
         , executable   = "z3"
         , preprocess   = id
         , options      = modConfig ["-nw", "-in", "-smt2"]
         , engine       = standardEngine "SBV_Z3" "SBV_Z3_OPTIONS"
         , capabilities = SolverCapabilities {
                                supportsQuantifiers        = True
                              , supportsUninterpretedSorts = True
                              , supportsUnboundedInts      = True
                              , supportsReals              = True
                              , supportsApproxReals        = True
                              , supportsIEEE754            = True
                              , supportsOptimization       = True
                              , supportsPseudoBooleans     = True
                              , supportsCustomQueries      = True
                              , supportsGlobalDecls        = True
                              , supportsFlattenedSequences = Just [ "(set-option :pp.max_depth      4294967295)"
                                                                  , "(set-option :pp.min_alias_size 4294967295)"
                                                                  ]
                              }
         }

 where modConfig :: [String] -> SMTConfig -> [String]
       modConfig opts _cfg = opts
