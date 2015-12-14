#lang typed/racket/base

(provide 𝑰)

(require
 racket/match racket/list
 "../utils/map.rkt" "../utils/set.rkt"
 "../ast/definition.rkt" "../ast/meta-functions.rkt"
 "../runtime/addr.rkt" "../runtime/val.rkt" "../runtime/env.rkt" "../runtime/path-inv.rkt"
 "../runtime/store.rkt" "../runtime/summ.rkt"
 "definition.rkt" "havoc.rkt")

(: 𝑰 : (Listof -module) (Listof -module-level-form) → -ς)
;; Load program to intial machine state
(define (𝑰 ms init-prim)

  ;; Generate havoc function and top-level expression
  (define-values (havoc e_hv) (gen-havoc ms))

  ;; Assuming each top-level variable binds a value for now.
  ;; TODO generalize.
  (define σ₀
    (for/fold ([σ : -σ (⊔ -σ⊥ (-α.def -havoc-id) havoc)])
              ([form init-prim])
      (match form
        ;; general top-level form
        [(? -e?) σ]
        [(-define-values _ ids e)
         (match ids
           [(list id)
            (define-values (σ* V) (alloc-e σ e))
            (⊔ σ* (-α.def (-id id 'Λ)) V)]
           [else
            (error '𝑰 "TODO: general top-level. For now can't handle `define-~a-values`"
                   (length ids))])]
        [(? -require?) σ]
        ;; provide
        [(-provide _ specs)
         (for/fold ([σ : -σ σ]) ([spec specs])
           (match-define (-p/c-item x c) spec)
           (define-values (σ₁ C) (alloc-e σ c))
           (define id (-id x 'Λ))
           (define σ₂ (⊔ σ₁ (-α.ctc id) C))
           (cond
             [(hash-has-key? σ₂ (-α.def id)) σ₂]
             [else (⊔ σ₂ (-α.def id) -●/V)]))]
        ;; submodule-form
        [(? -module?) (error '𝑰 "TODO: sub-module forms")])))

  (define top-exps
    (append-map
     (λ ([m : -module]) : (Listof (U -define-values -provide))
       (for/list ([e (-plain-module-begin-body (-module-body m))]
                  #:when (or (-define-values? e) (-provide? e)))
         e))
     ms))

  (define τ₀ (-τ e_hv -ρ⊥ -Γ⊤))
  (define Ξ₀ : -Ξ (hash τ₀ ∅))
  
  (define-values (E₀ κ₀)
    (match top-exps
      ['() (values (-↓ e_hv -ρ⊥) τ₀)]
      [(cons e† exps)
       (values e† (-kont (-φ.top exps e_hv) τ₀))]))

  (-ς E₀ -Γ⊤ κ₀ σ₀ Ξ₀ -M⊥))

(: alloc-e : -σ -e → (Values -σ -V))
(define (alloc-e σ e)
  
  (define (error-ambig)
    (error 'alloc-e "ambiguity when checking for flat contract"))
  
  (match e
    [(? -v?) (values σ (close-Γ -Γ⊤ (close e -ρ⊥)))]
    [(-ref (-id o 'Λ) _ _) (values σ (prim-name->unsafe-prim o))]
    [(-->i doms rst rng pos)
     (define-values (xs cs)
       (for/lists ([xs : (Listof Symbol)] [cs : (Listof -e)])
                  ([dom doms])
         (values (car dom) (cdr dom))))
     (define-values (σ* γs)
       (alloc-es σ (#|HACK|# -struct-info (-id '-> 'Λ) (length cs) ∅) pos cs))
     (define-values (σ** Rst)
       (match rst
         [#f (values σ* #f)]
         [(cons x c)
          (define-values (σ** C) (alloc-e σ* c))
          (define α (-α.fld (-id '-> 'Λ) pos (length cs)))
          (values (⊔ σ** α C) (list x c α))]))
     (define Doms
       (for/list : (Listof (List Symbol -?e -α)) ([x xs] [c cs] [γ γs])
         (list x c γ)))
     (values σ* (-=>i Doms Rst rng -ρ⊥ -Γ⊤))]
    [(-@ (-st-mk (and s (-struct-info (or ''vectorof 'vector/c) _ _)))
         cs (-src-loc _ pos))
     (define-values (σ* αs) (alloc-es σ s pos cs))
     (values σ* (-St s αs))]
    [(-@ (or 'and/c (-ref (-id 'and/c 'Λ) _ _)) (list c₁ c₂) l)
     (define pos (-src-loc-pos l))
     (define γ₁ (-α.and/c-l pos))
     (define γ₂ (-α.and/c-r pos))
     (define-values (σ₁ V₁) (alloc-e σ  c₁))
     (define-values (σ₂ V₂) (alloc-e (⊔ σ₁ γ₁ V₁) c₂))
     (define flat? (and (C-flat? V₁) (C-flat? V₂)))
     (values (⊔ σ₂ γ₂ V₂) (-And/C flat? γ₁ γ₂))]
    [(-@ (or 'or/c (-ref (-id 'or/c 'Λ) _ _)) (list c₁ c₂) l)
     (define pos (-src-loc-pos l))
     (define γ₁ (-α.or/c-l pos))
     (define γ₂ (-α.or/c-r pos))
     (define-values (σ₁ V₁) (alloc-e σ  c₁))
     (define-values (σ₂ V₂) (alloc-e (⊔ σ₁ γ₁ V₁) c₂))
     (define flat? (and (C-flat? V₁) (C-flat? V₂)))
     (values (⊔ σ₂ γ₂ V₂) (-Or/C flat? γ₁ γ₂))]
    [(-@ (or 'not/c (-ref (-id 'not/c 'Λ) _ _)) (list c) l)
     (define-values (σ* V) (alloc-e σ c))
     (define γ (-α.not/c (-src-loc-pos l)))
     (values (⊔ σ* γ V) (-Not/C γ))]
    [(-@ (or 'vectorof (-ref (-id 'vectorof 'Λ) _ _)) (list c) l)
     (define-values (σ* V) (alloc-e σ c))
     (define γ (-α.vectorof (-src-loc-pos l)))
     (values (⊔ σ* γ V) (-Vectorof γ))]
    [(-@ (or 'vector/c (-ref (-id 'vector/c 'Λ) _ _)) cs l)
     (define-values (σ* γs-rev)
       (let ([pos (-src-loc-pos l)])
         (for/fold ([σ : -σ σ] [γs-rev : (Listof -α.vector/c) '()])
                   ([(c i) (in-indexed cs)])
           (define-values (σ* V) (alloc-e σ c))
           (define γ (-α.vector/c pos i))
           (values (⊔ σ* γ V) (cons γ γs-rev)))))
     (values σ* (-Vector/C (reverse γs-rev)))]
    [(-struct/c s cs pos)
     (define id (-struct-info-id s))
     (define-values (σ* αs-rev flat?)
       (for/fold ([σ* : -σ σ] [αs-rev : (Listof -α.struct/c) '()] [flat? : Boolean #t])
                 ([(c i) (in-indexed cs)])
         (define-values (σ_i V) (alloc-e σ* c))
         (define α (-α.struct/c id pos i))
         (values (⊔ σ_i α V) (cons α αs-rev) (and flat? (C-flat? V)))))
     (values σ* (-St/C flat? s (reverse αs-rev)))]
    [e (error '𝑰 "TODO: execute general expression. For now can't handle ~a"
              (show-e e))]))

(: alloc-es : -σ -struct-info Integer (Listof -e) → (Values -σ (Listof -α)))
(define (alloc-es σ s pos es)
  #|FIXME|# (define id (-struct-info-id s))
            (define-values (σ* αs-rev)
              (for/fold ([σ* : -σ σ] [αs-rev : (Listof -α) '()])
                        ([(e i) (in-indexed es)])
                (define-values (σ** V) (alloc-e σ* e))
                (define α (-α.fld id pos i))
                (values (⊔ σ** α V) (cons α αs-rev))))
            (values σ* (reverse αs-rev)))
