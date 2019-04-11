#lang typed/racket/base

(provide exec^
         evl^
         app^
         mon^
         hv^
         gc^
         with-collapsed with-collapsed/R
         with-collapsing with-collapsing/R
         with-each-path
         with-each-ans
         for/ans)

(require (for-syntax racket/base
                     (only-in racket/list append-map)
                     racket/syntax
                     syntax/parse)
         racket/match
         racket/set
         typed/racket/unit
         bnf
         unreachable
         intern
         set-extras
         "../ast/signatures.rkt"
         "../runtime/signatures.rkt"
         ) 

;; HACK: Errors in the object language is tracked through a side channel `err!`
;; in the meta-language. This is ugly and prevents expressing error handling,
;; but simplifies several thigns and is sufficient for now.
(define-signature exec^ 
  ([exec : ((U E -prog) → (Values (℘ Err) $))]
   [ref-$! : ($:Key (→ R) → R)]
   [err! : ((U (℘ Err) Err) → Void)]
   [current-module : (Parameterof -l)]
   [blm : (-l ℓ ℓ W W → (℘ Blm))]
   [fold-ans : (∀ (X) (X → R) (℘ X) → R)]
   [fold-ans/collapsing : (∀ (X) (X → R) (℘ X) → R)]
   [with-split-Σ : (Σ V W (W ΔΣ → R) (W ΔΣ → R) → R)]
   [db:iter? : (Parameterof Boolean)]
   [db:max-steps : (Parameterof (Option Index))]
   [db:depth : (Parameterof Natural)]))

;; Σ ⊢ E ⇓ A , ΔΣ
(define-signature evl^
  ([evl-prog : (-prog → (Option ΔΣ))]
   [evl : (Σ E → R)]
   [escape-clos : (Σ W → (Values W ΔΣ))]
   [R-escape-clos : (Σ R → R)]))

;; Σ ⊢ V V… ⇓ᵃ A , ΔΣ
(define-signature app^
  ([app : (Σ ℓ V^ W → R)]
   [app/rest : (Σ ℓ V^ W V^ → R)]
   [st-ac-● : (-𝒾 Index (℘ P) Σ → V^)]))

;; Σ ⊢ V V ⇓ᵐ A , ΔΣ
(define-signature mon^
  ([mon : (Σ Ctx V^ V^ → R)]
   [mon* : (Σ Ctx W W → R)]))

(define-signature hv^
  ([leak : (Σ γ:hv V^ → R)]
   [gen-havoc-expr : ((Listof -module) → E)]
   [behavioral? : (V Σ → Boolean)]))

(define-signature gc^
  ([gc : ([(℘ α) Σ] [Σ] . ->* . Σ)]
   [clear-live-set-cache! : (→ Void)]
   [gc-R : ((℘ α) Σ R → R)]
   [V-root : (V → (℘ α))]
   [V^-root : (V^ → (℘ α))]
   [W-root : (W → (℘ α))]
   [E-root : (E → (℘ γ))]))

(define-syntax with-collapsed
  (syntax-parser
    [(_ [?x:expr e:expr]
        (~optional (~seq #:fail fail:expr) #:defaults ([fail #'#f]))
        body:expr ...)
     #'(match e
         [(? values ?x) (let-values () body ...)]
         [#f fail])]))
(define-syntax-rule (with-collapsed/R [?x e] body ...)
  (with-collapsed [?x e] #:fail ⊥R body ...))

(define-syntax with-collapsing
  (syntax-parser
    [(_ [(ΔΣ:id Ws) e:expr]
        (~optional (~seq #:fail fail:expr) #:defaults ([fail #'#f]))
        body:expr ...)
     (with-syntax ([collapse-R (format-id #'e "collapse-R")])
       #'(let ([r e])
           (match (collapse-R r)
             [(cons Ws ΔΣ) body ...]
             [#f fail])))]))
(define-syntax-rule (with-collapsing/R [(ΔΣ Ws) e] body ...)
  (with-collapsing [(ΔΣ Ws) e] #:fail ⊥R body ...))

(define-syntax with-each-path
  (syntax-parser
    [(_ [(ΔΣs₀ W₀) e] body ...)
     (with-syntax ([R⊔ (format-id #'e "R⊔")])
       #'(let ([r₀ e])
           (for/fold ([r* : R ⊥R]) ([(W₀ ΔΣs₀) (in-hash r₀)])
             (define r₁ (let () body ...))
             (R⊔ r* r₁))))]))

(define-syntax with-each-ans
  (syntax-parser
    [(with-each-ans ([(ΔΣᵢ Wᵢ) eᵢ] ...) body ...)
     (with-syntax ([R⊔ (format-id #'with-each-ans "R⊔")]
                   [collapse-ΔΣs (format-id #'with-each-ans "collapse-ΔΣs")])
       (define mk-clause
         (syntax-parser
           [(ΔΣᵢ Wᵢ eᵢ)
            (list
             #'[(Wᵢ ΔΣsᵢ) (in-hash eᵢ)]
             #'[ΔΣᵢ (in-value (collapse-ΔΣs ΔΣsᵢ))])]))
       #`(for*/fold ([r* : R ⊥R])
                    (#,@(append-map mk-clause (syntax->list #'([ΔΣᵢ Wᵢ eᵢ] ...))))
           (R⊔ r* (let () body ...))))]))


(define-syntax for/ans
  (syntax-parser
    [(for/ans (clauses ...) body ...)
     (with-syntax ([R⊔ (format-id #'for/ans "R⊔")])
       #'(for/fold ([r : R ⊥R]) (clauses ...)
           (R⊔ r (let () body ...))))]))
