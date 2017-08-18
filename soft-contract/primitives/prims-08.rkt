#lang typed/racket/base

(provide prims-08@)

(require racket/match
         racket/set
         racket/contract
         racket/splicing
         typed/racket/unit
         set-extras
         "../ast/signatures.rkt"
         "../runtime/signatures.rkt"
         "def-prim.rkt"
         "../signatures.rkt"
         "signatures.rkt")

(define-unit prims-08@
  (import prim-runtime^ proof-system^ widening^ val^ pc^ sto^ pretty-print^)
  (export)

  
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; 8.1 Data-structure Contracts
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (def-prim/todo flat-named-contract ; FIXME uses
    (any/c flat-contract? . -> . flat-contract?))
  (def-prim/custom (any/c ⟪ℋ⟫ ℓ Σ $ Γ Ws)
    #:domain ([W any/c])
    {set (-ΓA Γ (-W (list -tt) -tt))})
  (def-prim/custom (none/c ⟪ℋ⟫ ℓ Σ $ Γ Ws)
    #:domain ([W any/c])
    {set (-ΓA Γ (-W (list -ff) -ff))})

  (splicing-local
      
      ((: reduce-contracts : -l ℓ -Σ -Γ (Listof -W¹) (ℓ -W¹ -W¹ → (Values -V -?t)) -W → (℘ -ΓA))
       (define (reduce-contracts lo ℓ Σ Γ Ws comb id)
         (match Ws
           ['() {set (-ΓA Γ id)}]
           [_
            (define definite-error? : Boolean #f)
            (define maybe-errors
              (for/set: : (℘ -ΓA) ([W (in-list Ws)]
                                   #:when (case (Γ⊢oW (-Σ-σ Σ) Γ 'contract? W)
                                            [(✓)                       #f]
                                            [(✗) (set! definite-error? #t)]
                                            [(?)                        #t ]))
                (-ΓA Γ (-blm (ℓ-src ℓ) lo '(contract?) (list (-W¹-V W)) ℓ))))
            (cond [definite-error? maybe-errors]
                  [else
                   (define-values (V* t*)
                     (let loop : (Values -V -?t) ([Ws : (Listof -W¹) Ws] [i : Natural 0])
                          (match Ws
                            [(list (-W¹ V t)) (values V t)]
                            [(cons Wₗ Wsᵣ)
                             (define-values (Vᵣ tᵣ) (loop Wsᵣ (+ 1 i)))
                             (comb (ℓ-with-id ℓ i) Wₗ (-W¹ Vᵣ tᵣ))])))
                   (set-add maybe-errors (-ΓA Γ (-W (list V*) t*)))])])))
    
    (def-prim/custom (or/c ⟪ℋ⟫ ℓ₀ Σ $ Γ Ws)
      (: or/c.2 : ℓ -W¹ -W¹ → (Values -V -?t))
      (define (or/c.2 ℓ W₁ W₂)
        (match-define (-W¹ V₁ t₁) W₁)
        (match-define (-W¹ V₂ t₂) W₂)
        (define α₁ (-α->⟪α⟫ (-α.or/c-l ℓ ⟪ℋ⟫)))
        (define α₂ (-α->⟪α⟫ (-α.or/c-r ℓ ⟪ℋ⟫)))
        (σ⊕V! Σ α₁ V₁)
        (σ⊕V! Σ α₂ V₂)
        (define ℓ₁ (ℓ-with-id ℓ 'left-disj))
        (define ℓ₂ (ℓ-with-id ℓ 'right-disj))
        (define C (-Or/C (and (C-flat? V₁) (C-flat? V₂)) (-⟪α⟫ℓ α₁ ℓ₁) (-⟪α⟫ℓ α₂ ℓ₂)))
        (values C (?t@ 'or/c t₁ t₂)))
      (reduce-contracts 'or/c ℓ₀ Σ Γ Ws or/c.2 (+W (list 'none/c))))
    
    (def-prim/custom (and/c ⟪ℋ⟫ ℓ₀ Σ $ Γ Ws)
      (: and/c.2 : ℓ -W¹ -W¹ → (Values -V -?t))
      (define (and/c.2 ℓ W₁ W₂)
        (match-define (-W¹ V₁ t₁) W₁)
        (match-define (-W¹ V₂ t₂) W₂)
        (define α₁ (-α->⟪α⟫ (-α.and/c-l ℓ ⟪ℋ⟫)))
        (define α₂ (-α->⟪α⟫ (-α.and/c-r ℓ ⟪ℋ⟫)))
        (σ⊕V! Σ α₁ V₁)
        (σ⊕V! Σ α₂ V₂)
        (define ℓ₁ (ℓ-with-id ℓ 'left-conj))
        (define ℓ₂ (ℓ-with-id ℓ 'right-conj))
        (define C (-And/C (and (C-flat? V₁) (C-flat? V₂)) (-⟪α⟫ℓ α₁ ℓ₁) (-⟪α⟫ℓ α₂ ℓ₂)))
        (values C (?t@ 'and/c t₁ t₂)))
      (reduce-contracts 'and/c ℓ₀ Σ Γ Ws and/c.2 (+W (list 'any/c)))))

  (def-prim/custom (not/c ⟪ℋ⟫ ℓ Σ $ Γ Ws)
    #:domain ([W flat-contract?])
    (match-define (-W¹ V t) W)
    (define α (-α->⟪α⟫ (-α.not/c ℓ ⟪ℋ⟫)))
    (σ⊕V! Σ α V)
    (define ℓ* (ℓ-with-id ℓ 'not/c))
    (define C (-Not/C (-⟪α⟫ℓ α ℓ*)))
    {set (-ΓA Γ (-W (list C) (?t@ 'not/c t)))})
  (def-prim/todo =/c  (real? . -> . flat-contract?))
  (def-prim/todo </c  (real? . -> . flat-contract?))
  (def-prim/todo >/c  (real? . -> . flat-contract?))
  (def-prim/todo <=/c (real? . -> . flat-contract?))
  (def-prim/todo >=/c (real? . -> . flat-contract?))
  (def-prim/todo between/c (real? real? . -> . flat-contract?))
  [def-alias real-in between/c]
  (def-prim/todo integer-in (exact-integer? exact-integer? . -> . flat-contract?))
  (def-prim/todo char-in (char? char? . -> . flat-contract?))
  (def-prim/todo def-alias natural-number/c exact-nonnegative-integer?)
  (def-prim/todo string-len/c (real? . -> . flat-contract?))
  (def-alias false/c not)
  (def-pred printable/c)
  (def-prim/custom (one-of/c ⟪ℋ⟫ ℓ Σ $ Γ Ws)
    (define-values (vals ts.rev)
      (for/fold ([vals : (℘ Base) ∅] [ts : (Listof -?t) '()])
                ([W (in-list Ws)] [i (in-naturals)])
        (match W
          [(-W¹ (-b b) t) (values (set-add vals b) (cons t ts))]
          [W (error 'one-of/c
                    "only support simple values for now, got ~a at ~a~a position"
                    (show-W¹ W) i (case i [(1) 'st] [(2) 'nd] [else 'th]))])))
    (define Wₐ (-W (list (-One-Of/C vals)) (apply ?t@ 'one-of/c (reverse ts.rev))))
    {set (-ΓA Γ Wₐ)})
  #;[symbols
     (() #:rest (listof symbol?) . ->* . flat-contract?)]
  (def-prim/custom (vectorof ⟪ℋ⟫ ℓ Σ $ Γ Ws) ; FIXME uses
    #:domain ([W contract?])
    (match-define (-W¹ V t) W)
    (define ⟪α⟫ (-α->⟪α⟫ (-α.vectorof ℓ ⟪ℋ⟫)))
    (σ⊕V! Σ ⟪α⟫ V)
    (define C (-Vectorof (-⟪α⟫ℓ ⟪α⟫ (ℓ-with-id ℓ 'vectorof))))
    {set (-ΓA Γ (-W (list C) (?t@ 'vectorof t)))})
  (def-prim/todo vector-immutableof (contract? . -> . contract?))
  (def-prim/custom (vector/c ⟪ℋ⟫ ℓ₀ Σ $ Γ Ws)
    ; FIXME uses ; FIXME check for domains to be listof contract
    (define-values (αs ℓs ss) ; with side effect widening store
      (for/lists ([αs : (Listof ⟪α⟫)] [ℓs : (Listof ℓ)] [ts : (Listof -?t)])
                 ([W (in-list Ws)] [i (in-naturals)] #:when (index? i))
        (match-define (-W¹ V t) W)
        (define ⟪α⟫ (-α->⟪α⟫ (-α.vector/c ℓ₀ ⟪ℋ⟫ i)))
        (σ⊕V! Σ ⟪α⟫ V)
        (values ⟪α⟫ (ℓ-with-id ℓ₀ i) t)))
    (define C (-Vector/C (map -⟪α⟫ℓ αs ℓs)))
    {set (-ΓA Γ (-W (list C) (apply ?t@ 'vector/c ss)))})
  #;[vector-immutable/c
     (() #:rest (listof contract?) . ->* . contract?)]
  (def-prim/todo box/c ; FIXME uses
    (contract? . -> . contract?))
  (def-prim/todo box-immutable/c (contract? . -> . contract?))
  (def-prim/custom (listof ⟪ℋ⟫ ℓ Σ $ Γ Ws)
    #:domain ([W contract?])
    (match-define (-W¹ C c) W)
    (define flat? (C-flat? C))
    (define α₀ (-α->⟪α⟫ 'null?))
    (define α₁ (-α->⟪α⟫ (-α.or/c-r ℓ ⟪ℋ⟫)))
    (define αₕ (-α->⟪α⟫ (-α.struct/c -𝒾-cons ℓ ⟪ℋ⟫ 0)))
    (define αₜ (-α->⟪α⟫ (-α.struct/c -𝒾-cons ℓ ⟪ℋ⟫ 1)))
    (define αₗ (-α->⟪α⟫ (-α.x/c (+x!/memo 'listof ℓ))))
    (define ℓ₀ (ℓ-with-id ℓ 'null?))
    (define ℓ₁ (ℓ-with-id ℓ 'pair?))
    (define ℓₕ (ℓ-with-id ℓ 'elem))
    (define ℓₜ (ℓ-with-id ℓ 'rest))
    (define Disj (-Or/C flat? (-⟪α⟫ℓ α₀ ℓ₀) (-⟪α⟫ℓ α₁ ℓ₁)))
    (define Cons (-St/C flat? -𝒾-cons (list (-⟪α⟫ℓ αₕ ℓₕ) (-⟪α⟫ℓ αₜ ℓₜ))))
    (define Ref (-x/C αₗ))
    (σ⊕V! Σ αₗ Disj)
    (σ⊕V! Σ α₀ 'null?)
    (σ⊕V! Σ α₁ Cons)
    (σ⊕V! Σ αₕ C)
    (σ⊕V! Σ αₜ Ref)
    {set (-ΓA Γ (-W (list Ref) (?t@ 'listof c)))})
  (def-prim/todo non-empty-listof (contract? . -> . list-contract?))
  (def-prim/todo list*of (contract? . -> . contract?))
  (def-prim/todo cons/c (contract? contract? . -> . contract?))
  (def-prim/todo list/c (() #:rest (listof contract?) . ->* . list-contract?))
  (def-prim/todo syntax/c (flat-contract? . -> . flat-contract?))
  (def-prim/todo parameter/c ; FIXME uses
    (contract? . -> . contract?))
  (def-prim/todo procedure-arity-includes/c
    (exact-nonnegative-integer? . -> . flat-contract?))
  (def-prim/custom (hash/c ⟪ℋ⟫ ℓ Σ $ Γ Ws) ; FIXME uses
    #:domain ([Wₖ contract?] [Wᵥ contract?])
    (match-define (-W¹ _ tₖ) Wₖ)
    (match-define (-W¹ _ tᵥ) Wᵥ)
    (define αₖ (-α->⟪α⟫ (-α.hash/c-key ℓ ⟪ℋ⟫)))
    (define αᵥ (-α->⟪α⟫ (-α.hash/c-val ℓ ⟪ℋ⟫)))
    (σ⊕! Σ Γ αₖ Wₖ)
    (σ⊕! Σ Γ αᵥ Wᵥ)
    (define V (-Hash/C (-⟪α⟫ℓ αₖ (ℓ-with-id ℓ 'hash/c.key)) (-⟪α⟫ℓ αᵥ (ℓ-with-id ℓ 'hash/c.val))))
    {set (-ΓA Γ (-W (list V) (?t@ 'hash/c tₖ tᵥ)))})
  (def-prim/todo channel/c (contract? . -> . contract?))
  (def-prim/todo continuation-mark-key/c (contract? . -> . contract?))
  ;;[evt/c (() #:rest (listof chaperone-contract?) . ->* . chaperone-contract?)]
  (def-prim/todo promise/c (contract? . -> . contract?))
  (def-prim/todo flat-contract ((any/c . -> . any/c) . -> . flat-contract?))
  (def-prim/todo flat-contract-predicate (flat-contract? . -> . (any/c . -> . any/c)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; 8.2 Function Contracts
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  (def-opq predicate/c contract?)
  (def-opq the-unsupplied-arg unsupplied-arg?)
  (def-pred unsupplied-arg?)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; 8.8 Contract Utilities
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ; TODO
  (def-prim contract-first-order-passes?
    (contract? any/c . -> . boolean?))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; 8.8 Contract Utilities
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  (def-pred contract?)
  (def-pred chaperone-contract?)
  (def-pred impersonator-contract?)
  (def-pred flat-contract?)
  (def-pred list-contract?)
  (def-prim/todo contract-name (contract? . -> . any/c))
  (def-prim/todo value-contract (has-contract? . -> . (or/c contract? not)))
  [def-pred has-contract?]
  (def-prim/todo value-blame (has-blame? . -> . (or/c blame? not)))
  [def-pred has-blame?]
  (def-prim/todo contract-projection (contract? . -> . (blame? . -> . (any/c . -> . any/c))))
  (def-prim/todo make-none/c (any/c . -> . contract?))
  (def-opq contract-continuation-mark-key continuation-mark-key?))
