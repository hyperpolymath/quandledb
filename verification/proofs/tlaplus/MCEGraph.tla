------------------------------ MODULE MCEGraph ------------------------------
(* SPDX-License-Identifier: MPL-2.0                                        *)
(* Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)                 *)
(*                                                                         *)
(* TLC model harness for EGraphConfluence.  The `.cfg` format cannot write *)
(* tuple literals in CONSTANT assignments, so the concrete model values    *)
(* are defined here and supplied to the spec by `INSTANCE ... WITH`.        *)
(*                                                                         *)
(* Four knots; the merge facts chain them into one class, so TLC must      *)
(* confirm that every interleaving of merge order reaches the same final   *)
(* partition (confluence / deterministic collapse).                        *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets

MCElements == {1, 2, 3, 4}
MCMerges   == {<<1, 2>>, <<3, 4>>, <<2, 3>>}

VARIABLE rel

INSTANCE EGraphConfluence WITH Elements <- MCElements, Merges <- MCMerges
=============================================================================
