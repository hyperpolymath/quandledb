{-# OPTIONS --safe #-}
-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
-- ===========================================================================
-- Dihedral (Takasaki) quandle axioms  —  machine-checked under `agda --safe`
-- ===========================================================================
--
-- Discharges the algebraic core of obligation M1 ("Quandle axioms preserved")
-- from PROOF-NEEDS.md / PROOF-NARRATIVE.md, and underpins QD-8
-- (`_dihedral_colouring_count` correctness, which relies on the colouring
-- target actually being a quandle).
--
-- BEFORE (existing evidence): the three quandle axioms were *property-tested*
--   for the dihedral quandle Z_p at the five primes p ∈ {3, 5, 7, 11, 13}
--   (server/test_quandle_axioms.jl §1).
-- NOW (this file): the three axioms are *proved* for the dihedral / Takasaki
--   quandle operation over ℤ — i.e. for the universal (infinite) dihedral
--   quandle — for ALL arguments, with no case bound.
--
-- The dihedral quandle operation is  a ▷ b = 2·b − a  (= (b + b) − a):
--   1. idempotence            a ▷ a ≡ a
--   2. right self-distributivity   (a ▷ b) ▷ c ≡ (a ▷ c) ▷ (b ▷ c)
--   3. right-invertibility    x ↦ x ▷ b is a bijection
--                             (here: an involution, hence its own inverse)
--
-- Scope / honesty.  The mechanised result is over ℤ.  Every *finite* dihedral
-- quandle R_n = ℤ/nℤ (the Z_p of the tests) is a homomorphic image of ℤ under
-- the surjective ring homomorphism ℤ ↠ ℤ/n; the three axioms are equational
-- identities and so are preserved by homomorphic images.  Hence proving them
-- over ℤ establishes them for every R_n, including each Z_p the suite tests.
-- The quotient step itself is the standard algebra remark, not mechanised here.
--
-- This file does NOT address QD-1 (that `extract_presentation` yields a valid
-- Wirtinger presentation) — that is a separate, harder obligation.

module DihedralQuandle where

open import Data.Integer using (ℤ; _+_; _-_; +_)
open import Data.Integer.Solver renaming (module +-*-Solver to ℤ-solver)
open import Data.Product using (∃; _,_)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong)

open ℤ-solver

-- The dihedral / Takasaki quandle operation:  a ▷ b = 2b − a.
infixr 5 _▷_
_▷_ : ℤ → ℤ → ℤ
a ▷ b = (b + b) - a

-- ───────────────────────────────────────────────────────────────────────────
-- Axiom 1 — idempotence:  a ▷ a ≡ a.
--   (a + a) − a ≡ a.   A polynomial identity over the ring ℤ.
-- ───────────────────────────────────────────────────────────────────────────
idempotent : ∀ a → a ▷ a ≡ a
idempotent = solve 1 (λ a → ((a :+ a) :- a) := a) refl

-- ───────────────────────────────────────────────────────────────────────────
-- Axiom 3 — right self-distributivity:
--   (a ▷ b) ▷ c ≡ (a ▷ c) ▷ (b ▷ c).
--   Both sides normalise to  a − 2b + 2c  over ℤ.
-- ───────────────────────────────────────────────────────────────────────────
self-distrib : ∀ a b c → (a ▷ b) ▷ c ≡ (a ▷ c) ▷ (b ▷ c)
self-distrib = solve 3
  (λ a b c →
      ((c :+ c) :- ((b :+ b) :- a))
    := ((((c :+ c) :- b) :+ ((c :+ c) :- b)) :- ((c :+ c) :- a)))
  refl

-- ───────────────────────────────────────────────────────────────────────────
-- Axiom 2 — right-invertibility:  the right translation  Sᵦ : x ↦ x ▷ b
-- is a bijection.  We show it is an *involution* (Sᵦ ∘ Sᵦ ≡ id), which makes
-- it its own two-sided inverse; injectivity and surjectivity then follow.
-- ───────────────────────────────────────────────────────────────────────────

-- Sᵦ is an involution:  (a ▷ b) ▷ b ≡ a.
right-involutive : ∀ a b → (a ▷ b) ▷ b ≡ a
right-involutive = solve 2 (λ a b → ((b :+ b) :- ((b :+ b) :- a)) := a) refl

-- … hence Sᵦ is injective.
right-injective : ∀ {a a′} b → a ▷ b ≡ a′ ▷ b → a ≡ a′
right-injective {a} {a′} b eq =
  trans (sym (right-involutive a b))
        (trans (cong (_▷ b) eq) (right-involutive a′ b))

-- … and Sᵦ is surjective:  every y is hit, by the preimage (y ▷ b).
right-surjective : ∀ y b → ∃ λ x → x ▷ b ≡ y
right-surjective y b = (y ▷ b) , right-involutive y b

-- ───────────────────────────────────────────────────────────────────────────
-- Concrete computational sanity (each is `refl` — the operation actually runs)
-- ───────────────────────────────────────────────────────────────────────────

-- In the dihedral quandle of ℤ:  3 ▷ 5 = 2·5 − 3 = 7.
_ : (+ 3) ▷ (+ 5) ≡ + 7
_ = refl

-- idempotence at a concrete point:  5 ▷ 5 = 5.
_ : (+ 5) ▷ (+ 5) ≡ + 5
_ = refl
