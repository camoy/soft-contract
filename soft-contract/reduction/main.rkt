#lang typed/racket/base

(provide run-files run run-e)

(require
 racket/match racket/set
 "../utils/main.rkt"
 "../ast/main.rkt"
 "../parse/main.rkt"
 "../runtime/main.rkt"
 (only-in "../proof-relation/main.rkt" Γ⊢ₑₓₜ)
 (only-in "../proof-relation/ext/z3.rkt" z3⊢)
 "step.rkt" "init.rkt")

(: run-files : Path-String * → (℘ -A))
(define (run-files . ps)
  (define ms (files->modules ps))
  (define-values (σ₀ e₀) (𝑰 ms))
  (define-values (As M Ξ σ) (run (⇓ₚ ms e₀) σ₀))
  As)

(: run-e : -e → (Values Sexp #|for debugging|# Sexp Sexp Sexp))
(define (run-e e)
  (define-values (As M Ξ σ) (run (⇓ e) ⊥σ))
  (values (set-map As show-A) (show-M M) (show-Ξ Ξ) (show-σ σ)))

(: run : -⟦e⟧ -σ → (Values (℘ -A) #|for debugging|# -M -Ξ -σ))
;; Run compiled program on initial heap
(define (run ⟦e⟧₀ σ₀)
  
  (: loop : (HashTable -ℬ -σ) (℘ -ℬ) (℘ -Co) -M -Ξ -σ → (Values -M -Ξ -σ))
  (define (loop seen ℬs Cos M Ξ σ)
    (cond
      [(and (set-empty? ℬs) (set-empty? Cos))
       (values M Ξ σ)]
      [else
       
       ;; Widen global tables
       (define-values (δM δΞ δσ) (⊔³ (ev* M Ξ σ ℬs) (co* M Ξ σ Cos)))
       (define-values (M* Ξ* σ*) (⊔³ (values M Ξ σ) (values δM δΞ δσ)))

       #;(begin
         (printf "δM:~n~a~n" (show-M δM))
         (printf "δΞ:~n~a~n" (show-Ξ δΞ))
         (printf "δσ:~n~a~n" (show-σ δσ))
         (printf "~n"))

       ;; Check for un-explored configuation (≃ ⟨e, ρ, σ⟩)
       (define-values (ℬs* seen*)
         (for/fold ([ℬs* : (℘ -ℬ) ∅] [seen* : (HashTable -ℬ -σ) seen])
                   ([ℬ (in-hash-keys δΞ)] #:unless (equal? (hash-ref seen -ℬ #f) σ*))
           (values (set-add ℬs* ℬ) (hash-set seen* ℬ σ*))))
       (define Cos*
         (∪ (for*/set: : (℘ -Co) ([(ℬ As) (in-hash δM)] #:unless (set-empty? As)
                                  [ℛ (in-set (Ξ@ Ξ* ℬ))])
              (-Co ℛ As))
            (for*/set: : (℘ -Co) ([(ℬ ℛs) (in-hash δΞ)]
                                  [As (in-value (M@ M* ℬ))] #:unless (set-empty? As)
                                  [ℛ (in-set ℛs)])
              (-Co ℛ As))))
       
       (loop seen* ℬs* Cos* M* Ξ* σ*)]))

  (define ℬ₀ (-ℬ ⟦e⟧₀ ⊥ρ))
  (define-values (M Ξ σ)
    (parameterize ([Γ⊢ₑₓₜ z3⊢])
      (loop (hash ℬ₀ σ₀) {set ℬ₀} ∅ ⊥M ⊥Ξ σ₀)))
  (values (M@ M ℬ₀) M Ξ σ))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; Helpers
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-syntax-rule (⊔³ x y)
  (let-values ([(x₁ x₂ x₃) x]
               [(y₁ y₂ y₃) y])
    (values (⊔/m x₁ y₁) (⊔/m x₂ y₂) (⊔/m x₃ y₃))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; Test
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


(module+ test
  (require typed/rackunit)
  
  (define -Y
    (-λ '(f)
     (-λ '(x)
      (-@ (-@ (-λ '(g) (-@ (-x 'f) (list (-λ '(x) (-@ (-@ (-x 'g) (list (-x 'g)) -Λ) (list (-x 'x)) -Λ))) -Λ))
              (list (-λ '(g) (-@ (-x 'f) (list (-λ '(x) (-@ (-@ (-x 'g) (list (-x 'g)) -Λ) (list (-x 'x)) -Λ))) -Λ)))
              -Λ)
          (list (-x 'x))
          -Λ))))
  (define -rep
    (-λ '(rep)
     (-λ '(n)
      (-if (-@ 'zero? (list (-x 'n)) -Λ)
           (-b 0)
           (-@ 'add1 (list (-@ (-x 'rep) (list (-@ 'sub1 (list (-x 'n)) -Λ)) -Λ)) -Λ)))))
  (define -rep-prog
    (α-rename (-@ (-@ -Y (list -rep) -Λ) (list (-b 0)) -Λ)))
  )
