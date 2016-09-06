#lang typed/racket/base

(require "../utils/main.rkt"
         "../ast/main.rkt"
         "../parse/main.rkt"
         "../runtime/main.rkt"
         "../proof-relation/main.rkt"
         "compile/kontinuation.rkt"
         "compile/main.rkt"
         "init.rkt"
         racket/set
         racket/match)

(: run-file : Path-String → (Values (℘ -A) -Σ))
(define (run-file p)
  (define m (file->module p))
  (define-values (σ₁ _) (𝑰 (list m)))
  (run (↓ₘ m) σ₁))

(: havoc-file : Path-String → (Values (℘ -A) -Σ))
(define (havoc-file p)
  (define m (file->module p))
  (define-values (σ₁ e₁) (𝑰 (list m)))
  (run (↓ₚ (list m) e₁) σ₁))

(: run-e : -e → (Values (℘ -A) -Σ))
(define (run-e e)
  (define-values (σ₀ _) (𝑰 '()))
  (run (↓ₑ 'top e) σ₀))

(: run : -⟦e⟧! -σ → (Values (℘ -A) -Σ))
(define (run ⟦e⟧! σ)
  (define Σ (-Σ σ (⊥σₖ) (⊥M)))
  (define seen : (HashTable -ς (List Fixnum Fixnum Fixnum)) (make-hash))
  (define αₖ₀ : -αₖ (-ℬ ⟦e⟧! ⊥ρ))

  (let loop! ([front : (℘ -ς) {set (-ς↑ αₖ₀ ⊤Γ 𝒞∅)}])
    (unless (set-empty? front)
      (define v-Σ
        (let-values ([(v-σ v-σₖ v-M) (-Σ-version Σ)])
          (list v-σ v-σₖ v-M)))
      (define next
        (for/union : (℘ -ς) ([ς front] #:unless (equal? v-Σ (hash-ref seen ς (λ () #f))))
          (hash-set! seen ς v-Σ)
          (↝! ς Σ)))
      (loop! next)))

  (match-let ([(-Σ σ σₖ M) Σ])
    (values (map/set -ΓA-ans (M@ M αₖ₀))
            Σ)))

(: ↝! : -ς -Σ → (℘ -ς))
;; Perform one "quick-step" on configuration,
;; Producing set of next configurations and store-deltas
(define (↝! ς Σ)
  (match ς
    [(-ς↑ αₖ Γ 𝒞) (↝↑! αₖ Γ 𝒞 Σ)]
    [(-ς↓ αₖ Γ A) (↝↓! αₖ Γ A Σ)]))

(: ↝↑! : -αₖ -Γ -𝒞 -Σ → (℘ -ς))
;; Quick-step on "push" state
(define (↝↑! αₖ Γ 𝒞 Σ)
  (match αₖ
    [(-ℬ ⟦e⟧! ρ)
     (⟦e⟧! ρ Γ 𝒞 Σ (rt αₖ))]
    [_ (error '↝↑ "~a" αₖ)]))

(: ↝↓! : -αₖ -Γ -A -Σ → (℘ -ς))
;; Quick-step on "pop" state
(define (↝↓! αₖ Γₑₑ A Σ)
  (match-define (-Σ _ σₖ _) Σ)
  (for/union : (℘ -ς) ([κ (σₖ@ σₖ αₖ)])
    (match-define (-κ ⟦k⟧ Γₑᵣ 𝒞ₑᵣ bnd) κ)
    ;; TODO:
    ;; - eliminate conflicting path-conditions
    ;; - strengthen Γₑᵣ with path-condition address if it's plausible
    (define Γₑᵣ* Γₑᵣ)
    (match A
      [(-W Vs s)
       (define sₐ (and s (binding->s bnd)))
       (⟦k⟧ (-W Vs sₐ) Γₑᵣ* 𝒞ₑᵣ Σ)]
      [(? -blm? blm) ; TODO: faster if had next `αₖ` here 
       (⟦k⟧ blm Γₑᵣ* 𝒞ₑᵣ Σ)])))
