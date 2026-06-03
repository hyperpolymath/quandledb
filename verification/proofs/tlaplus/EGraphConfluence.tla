-------------------------- MODULE EGraphConfluence --------------------------
(***************************************************************************)
(* SPDX-License-Identifier: MPL-2.0                                        *)
(* Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)                 *)
(*                                                                         *)
(* Equality-saturation confluence for the QuandleDB equivalence engine.   *)
(*                                                                         *)
(* Discharges the model-checked core of two invariants from               *)
(* spec/operational-semantics.md:                                         *)
(*   §11.5  E-graph confluence:                                           *)
(*          "Equality saturation reaches a unique fixed point regardless  *)
(*           of rule application order."                                  *)
(*   §11.6  Deterministic collapse:                                       *)
(*          "Given the same database state and query, results are         *)
(*           deterministic."                                              *)
(*                                                                         *)
(* Model.  `Elements` are knots (e-classes initially singletons).         *)
(* `Merges` are the merge facts produced by rule firing (saturate, §8.1). *)
(* A step applies any not-yet-absorbed merge and re-closes the relation   *)
(* to an equivalence.  TLC explores EVERY interleaving of merge order;    *)
(* the property `Confluent` asserts every terminal partition equals the   *)
(* order-independent target `Saturated` — i.e. confluence.                *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets

CONSTANTS Elements,   \* finite set of e-class representatives (knots)
          Merges      \* set of <<a,b>> merge facts emitted by the rules

ASSUME MergesArePairs ==
    /\ Merges \subseteq (Elements \X Elements)

VARIABLE rel          \* current equivalence relation, as a set of pairs

----------------------------------------------------------------------------
(* One relational composition step and the reflexive/symmetric/transitive *)
(* closure to an equivalence relation (finite ⇒ the fixpoint terminates). *)

Diagonal == { <<x, x>> : x \in Elements }

Sym(R) == R \cup { <<p[2], p[1]>> : p \in R }

Step(R) ==
    R \cup { <<a, c>> \in Elements \X Elements :
                \E b \in Elements : <<a, b>> \in R /\ <<b, c>> \in R }

RECURSIVE Close(_)
Close(R) == LET R1 == Step(R) IN IF R1 = R THEN R ELSE Close(R1)

\* reflexive-symmetric-transitive closure of a base relation
EquivClosure(base) == Close(Sym(base) \cup Diagonal)

----------------------------------------------------------------------------
(* The order-independent target: close ALL merge facts at once.           *)
Saturated == EquivClosure(Merges)

(* A merge fact is absorbed once both endpoints already share a class.    *)
Absorbed(m) == <<m[1], m[2]>> \in rel
Done        == \A m \in Merges : Absorbed(m)

----------------------------------------------------------------------------
Init == rel = Diagonal

\* apply one not-yet-absorbed merge and re-saturate
MergeStep ==
    /\ \E m \in Merges :
          /\ ~ Absorbed(m)
          /\ rel' = EquivClosure(rel \cup {m})

\* stutter once fully saturated (so a finished run is not a deadlock)
Finish == Done /\ UNCHANGED rel

Next == MergeStep \/ Finish

Spec == Init /\ [][Next]_rel

----------------------------------------------------------------------------
(* ---- INVARIANTS (checked across every interleaving) ---- *)

\* rel is always a well-formed relation on Elements
TypeOK == rel \subseteq (Elements \X Elements)

\* rel is always an equivalence relation
IsEquivalence ==
    /\ \A x \in Elements : <<x, x>> \in rel                       \* reflexive
    /\ \A p \in rel : <<p[2], p[1]>> \in rel                      \* symmetric
    /\ \A a, b, c \in Elements :
          (<<a, b>> \in rel /\ <<b, c>> \in rel) => <<a, c>> \in rel  \* transitive

\* rel never over-merges: it stays below the saturated target
SoundBelow == rel \subseteq Saturated

\* CONFLUENCE / DETERMINISTIC COLLAPSE:
\* every saturated terminal state equals the order-independent target.
Confluent == Done => (rel = Saturated)

=============================================================================
