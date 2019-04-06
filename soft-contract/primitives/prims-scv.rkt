#lang typed/racket/base

(provide prims-scv@)

(require racket/match
         racket/contract
         typed/racket/unit
         racket/set
         unreachable
         set-extras
         "../utils/debug.rkt"
         "../utils/list.rkt"
         "../utils/patterns.rkt"
         (except-in "../ast/signatures.rkt" normalize-arity arity-includes?)
         "../runtime/signatures.rkt"
         "../execution/signatures.rkt"
         "../signatures.rkt"
         "signatures.rkt"
         "def.rkt"
         (for-syntax racket/base
                     racket/syntax
                     syntax/parse))

(define-unit prims-scv@
  (import static-info^
          prim-runtime^
          sto^ val^ cache^
          app^ mon^ exec^
          prover^)
  (export)

  (def (scv:mon Σ ℓ W)
    #:init ([src symbol?] [C contract?] [V any/c])
    (match src
      [(or {singleton-set (-b (? symbol? name))})
       (define l (current-module))
       (define ctx (Ctx l #|TODO|# l ℓ ℓ))
       (mon Σ ctx C V)]
      [_ (error 'scv:mon "internal error")]))

  ;; TODO: obsolete. Can be expressed directly in big step
  (def (scv:struct/c Σ ℓ W)
    #:init ([Vₖ any/c])
    #:rest [Wᵣ (listof contract?)]
    ((inst fold-ans V)
     (match-lambda
       [(-st-mk 𝒾)
        (if (= (count-struct-fields 𝒾) (length Wᵣ))
            (let ([α (α:dyn (β:st/c-elems ℓ 𝒾) H₀)])
              (R-of (St/C α) (alloc α (list->vector Wᵣ))))
            (begin (err! (Err:Arity (-𝒾-name 𝒾) Wᵣ ℓ))
                   ⊥R))]
       [_ (err! (blm (ℓ-src ℓ) ℓ +ℓ₀ (list {set 'constructor?}) (list Vₖ)))
          ⊥R])
     (unpack Vₖ Σ)))

  (def (scv:hash-key Σ ℓ W)
    #:init ([Vₕ hash?])
    (define ac₁ : (V → R)
      (match-lambda
        [(Empty-Hash) (err! (Blm (ℓ-src ℓ) ℓ (ℓ-with-src ℓ 'hash-ref)
                                 (list {set (Not/C (γ:imm 'hash-empty?) +ℓ₀)})
                                 (list {set (Empty-Hash)})))
                      ⊥R]
        [(Hash-Of αₖ _) (R-of (Σ@ αₖ Σ))]
        [(Guarded (cons l+ l-) (Hash/C αₖ _ ℓₕ) α)
         (define ctx (Ctx l+ l- ℓₕ ℓ))
         (with-collapsing/R [(ΔΣ Ws) (app Σ ℓₕ {set 'scv:hash-key} (list (Σ@ α Σ)))]
           (ΔΣ⧺R ΔΣ (mon (⧺ Σ ΔΣ) ctx (Σ@ αₖ Σ) (car (collapse-W^ Ws)))))]
        [(? -●?) (R-of (-● ∅))]
        [(? α? α) (fold-ans ac₁ (Σ@ α Σ))]
        [_ !!!]))
    (fold-ans/collapsing ac₁ Vₕ))

  (def (scv:hash-val Σ ℓ W)
    #:init ([Vₕ hash?])
    (define ac₁ : (V → R)
      (match-lambda
        [(Empty-Hash) (err! (Blm (ℓ-src ℓ) ℓ (ℓ-with-src ℓ 'hash-ref)
                                 (list {set (Not/C (γ:imm 'hash-empty?) +ℓ₀)})
                                 (list {set (Empty-Hash)})))
                      ⊥R]
        [(Hash-Of _ αᵥ) (R-of (Σ@ αᵥ Σ))]
        [(Guarded (cons l+ l-) (Hash/C _ αᵥ ℓₕ) α)
         (define ctx (Ctx l+ l- ℓₕ ℓ))
         (with-collapsing/R [(ΔΣ Ws) (app Σ ℓₕ {set 'scv:hash-val} (list (Σ@ α Σ)))]
           (ΔΣ⧺R ΔΣ (mon (⧺ Σ ΔΣ) ctx (Σ@ αᵥ Σ) (car (collapse-W^ Ws)))))]
        [(? -●?) (R-of (-● ∅))]
        [(? α? α) (fold-ans ac₁ (Σ@ α Σ))]
        [_ !!!]))
    (fold-ans/collapsing ac₁ Vₕ))

  ;; HACK for some internal uses of `make-sequence`
  (def (make-sequence Σ ℓ W)
    #:init ()
    #:rest [_ (listof any/c)]
    (R-of (list {set -car} {set -cdr} {set 'values} {set -one} {set -cons?} {set -ff} {set -ff})))
  )
