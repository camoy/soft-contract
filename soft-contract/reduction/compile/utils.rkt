#lang typed/racket/base

(provide (all-defined-out))

(require (for-syntax racket/base
                     racket/syntax
                     syntax/parse)
         racket/match
         racket/set
         racket/splicing
         syntax/parse/define
         "../../settings.rkt"
         "../../utils/main.rkt"
         "../../runtime/main.rkt"
         "../../proof-relation/main.rkt")


(splicing-let-syntax ([compute-frame-roots
                       (syntax-parser
                         [(_) #'∅eq]
                         [(_ root:id) #'(->⟪α⟫s root)]
                         [(_ root:id ...) #'(∪ (->⟪α⟫s root) ...)])])
  (define-simple-macro (with-error-handling (⟦k⟧:id A:id $:id Γ:id ⟪ℋ⟫:id Σ:id)
                         #:roots (root:id ...)
                         e ...)
    (let ([αₖ (⟦k⟧->αₖ ⟦k⟧)]
          [frame-roots (compute-frame-roots root ...)]
          [tail-roots (⟦k⟧->roots ⟦k⟧)])
      (define ⟦k⟧₀ (rt αₖ))
      (define ⟦k⟧* : -⟦k⟧
        (λ (A $ Γ ⟪ℋ⟫ Σ)
          (cond [(-blm? A) (⟦k⟧₀ A $ Γ ⟪ℋ⟫ Σ)]
                [else e ...])))
      (set-⟦k⟧->αₖ! ⟦k⟧* αₖ)
      (add-⟦k⟧-roots! ⟦k⟧* (∪ frame-roots tail-roots))
      ⟦k⟧*)))


(splicing-local
    ((define print-cache : (HashTable -blm Void) (make-hash)))

  ;; Base continuation that returns locally finished configuration
  (define/memo (rt [αₖ : -αₖ]) : -⟦k⟧
    (let ()
      (define ⟦k⟧ : -⟦k⟧
        (λ (A $ Γ ⟪ℋ⟫ Σ)
          (define (maybe-print-blame)
            (when (and (debug-iter?)
                       (-blm? A)
                       (= 0 (set-count (σₖ@ (-Σ-σₖ Σ) αₖ))))
              (hash-ref! print-cache
                         A
                         (λ ()
                           (printf "~a~n" (show-blm A))))))
          (match A
            [(-blm l+ _ _ _ _) #:when (symbol? l+) ; ignore blames on system
             ∅]
            [_
             (match-define (-Σ _ _ M) Σ)
             (define A*
               (match A
                 [(-W (list V) s) (-W (list (V+ (-Σ-σ Σ) V (predicates-of Γ s))) s)]
                 [_ A]))
             (unless (-ℋ𝒱? αₖ)
               (M⊕! Σ αₖ Γ A*))
             (maybe-print-blame)
             {set (-ς↓ αₖ Γ A*)}])))
      (set-⟦k⟧->αₖ! ⟦k⟧ αₖ)
      (add-⟦k⟧-roots! ⟦k⟧ ∅eq)
      ⟦k⟧)))
