#lang typed/racket/base

;; Each function `↝._` implements semantics of corresponding continuation frame,
;; returning ⟦e⟧→⟦e⟧.
;; This is factored out because it's used in both compilation `⇓` and resumption `ℰ⟦_⟧`.

(provide (all-defined-out)
         (all-from-out "continuation-if.rkt")
         (all-from-out "ap.rkt"))

(require
 racket/match racket/set racket/list
 "../utils/main.rkt"
 "../ast/main.rkt"
 "../runtime/main.rkt"
 "../proof-relation/main.rkt"
 "helpers.rkt"
 "continuation-if.rkt"
 "ap.rkt")

(: ↝.def : Mon-Party (Listof (U -α.def -α.wrp)) → -⟦ℰ⟧)
;; Define top-level `xs` to be values from `⟦e⟧`
(define (((↝.def l αs) ⟦e⟧) M σ ℒ)
  (apply/values
   (acc
    σ
    (λ (ℰ) (-ℰ.def l αs ℰ))
    (λ (σ* Γ* W)
      (define Vs (-W-Vs W))
      (with-guarded-arity (length αs) (l Γ* Vs)
        (define δσ
          (for/fold ([δσ : -Δσ ⊥σ]) ([α αs] [V Vs])
            (⊔ δσ α V)))
        (values δσ {set (-ΓW Γ* -Void/W)} ∅ ∅))))
    (⟦e⟧ M σ ℒ)))

(: ↝.dec : -𝒾 -ℓ → -⟦ℰ⟧)
;; Make `⟦c⟧`. the contract for `𝒾`.
(define (((↝.dec 𝒾 ℓ) ⟦c⟧) M σ ℒ)
  (apply/values
   (acc
    σ
    (λ (ℰ) (-ℰ.dec 𝒾 ℰ ℓ))
    (λ (σ* Γ* W)
      (match-define (-W Vs c) W)
      (define l (-𝒾-ctx 𝒾))
      (with-guarded-arity 1 (l Γ* Vs)
        (match-define (list C) Vs)
        (define ℒ* (-ℒ-with-Γ ℒ Γ*))
        (define ⟦ℰ⟧-wrp (↝.def l (list (-α.wrp 𝒾))))
        (define v (-ref 𝒾 0))
        (define W-C (-W¹ C c))
        (define l³ (Mon-Info l 'dummy l))
        (for*/ans ([V (σ@ σ (-α.def 𝒾))])
          ((⟦ℰ⟧-wrp (mon l³ ℓ W-C (-W¹ V v))) M σ* ℒ*)))))
   (⟦c⟧ M σ ℒ)))

(: ↝.begin : (Listof -⟦e⟧) → -⟦ℰ⟧)
(define ((↝.begin ⟦e⟧s) ⟦e⟧)
  (match ⟦e⟧s
    ['() ⟦e⟧]
    [(cons ⟦e⟧* ⟦e⟧s*)
     (define ⟦eᵣ⟧ ((↝.begin ⟦e⟧s*) ⟦e⟧*))
     (λ (M σ ℒ)
       (apply/values
        (acc
         σ
         (λ (ℰ) (-ℰ.begin ℰ ⟦e⟧s))
         (λ (σ* Γ* _) (⟦eᵣ⟧ M σ* (-ℒ-with-Γ ℒ Γ*))))
        (⟦e⟧ M σ ℒ)))]))

(: ↝.begin0.v : (Listof -⟦e⟧) → -⟦ℰ⟧)
;; Waiting on `⟦e⟧` to be the returned value for `begin0`
(define ((↝.begin0.v ⟦e⟧s) ⟦e⟧)
  (match ⟦e⟧s
    ['() ⟦e⟧]
    [(cons ⟦e⟧* ⟦e⟧s*)
     (λ (M σ ℒ)
       (apply/values
        (acc
         σ
         (λ (ℰ) (-ℰ.begin0.v ℰ ⟦e⟧s))
         (λ (σ* Γ* W)
           (define ⟦eᵣ⟧ ((↝.begin0.e W ⟦e⟧s*) ⟦e⟧*))
           (⟦eᵣ⟧ M σ* (-ℒ-with-Γ ℒ Γ*))))
        (⟦e⟧ M σ ℒ)))]))

(: ↝.begin0.e : -W (Listof -⟦e⟧) → -⟦ℰ⟧)
(define ((↝.begin0.e W ⟦e⟧s) ⟦e⟧)
  (match ⟦e⟧s
    ['()
     (λ (M σ ℒ)
       (values ⊥σ {set (-ΓW (-ℒ-cnd ℒ) W)} ∅ ∅))]
    [(cons ⟦e⟧* ⟦e⟧s*)
     (define ⟦e⟧ᵣ ((↝.begin0.e W ⟦e⟧s*) ⟦e⟧*))
     (λ (M σ ℒ)
       (apply/values
        (acc
         σ
         (λ (ℰ) (-ℰ.begin0.e W ℰ ⟦e⟧s))
         (λ (σ* Γ* _)
           (⟦e⟧ᵣ M σ* (-ℒ-with-Γ ℒ Γ*))))
        (⟦e⟧ M σ ℒ)))]))

(: ↝.let-values : Mon-Party
                  (Listof (Pairof Symbol -W¹))
                  (Listof Symbol)
                  (Listof (Pairof (Listof Symbol) -⟦e⟧))
                  -⟦e⟧
                  → -⟦ℰ⟧)
(define (((↝.let-values l x-Ws xs xs-⟦e⟧s ⟦e⟧) ⟦eₓ⟧) M σ ℒ)
  (apply/values
   (acc
    σ
    (λ (ℰ) (-ℰ.let-values l x-Ws (cons xs ℰ) xs-⟦e⟧s ⟦e⟧))
    (λ (σ* Γ* W)
      (match-define (-W Vs s) W)
      (define n (length xs))
      (with-guarded-arity n (l Γ* Vs)
        (define x-Ws*
          (foldr
           (λ ([x : Symbol] [V : -V] [s : -s] [x-Ws* : (Listof (Pairof Symbol -W¹))])
             (cons (cons x (-W¹ V s)) x-Ws*))
           x-Ws
           xs
           Vs
           (split-values s n)))
        (match xs-⟦e⟧s ; TODO dispatch outside?
          ['()
           (match-define (-ℒ ρ _ 𝒞) ℒ)
           (define-values (ρ* δσ Γ**)
             (for/fold ([ρ* : -ρ ρ] [δσ : -Δσ ⊥σ] [Γ** : -Γ Γ*])
                       ([x-W x-Ws*])
               (match-define (cons x (-W¹ V s)) x-W)
               (define α (-α.x x 𝒞))
               (values (hash-set ρ* x α)
                       (⊔ δσ α V)
                       (-Γ-with-aliases Γ* x s))))
           (define σ** (⊔/m σ* δσ))
           (⊔/ans (values δσ ∅ ∅ ∅)
                  (⟦e⟧ M σ** (-ℒ ρ* Γ** 𝒞)))]
          [(cons (cons xs* ⟦e⟧*) xs-⟦e⟧s*)
           (((↝.let-values l x-Ws* xs* xs-⟦e⟧s* ⟦e⟧) ⟦e⟧*) M σ* (-ℒ-with-Γ ℒ Γ*))]
          ))))
   (⟦eₓ⟧ M σ ℒ)))

(: ↝.letrec-values : Mon-Party
                     -Δρ
                     (Listof Symbol)
                     (Listof (Pairof (Listof Symbol) -⟦e⟧))
                     -⟦e⟧
                     → -⟦ℰ⟧)
(define (((↝.letrec-values l δρ xs xs-⟦e⟧s ⟦e⟧) ⟦eₓ⟧) M σ ℒ)
  ;; FIXME: inefficient. `ρ*` is recomputed many times
  (define ρ (-ℒ-env ℒ))
  (define ℒ* (-ℒ-with-ρ ℒ (ρ++ ρ δρ)))
  (apply/values
   (acc
    σ
    (λ (ℰ) (-ℰ.letrec-values l δρ (cons xs ℰ) xs-⟦e⟧s ⟦e⟧))
    (λ (σ₀ Γ₀ W)
      (define n (length xs))
      (match-define (-W Vs s) W)
      (with-guarded-arity n (l Γ₀ Vs)
        ;; Update/widen store and path condition
        (define-values (δσ Γ₁)
          (for/fold ([δσ : -Δσ ⊥σ] [Γ₁ : -Γ Γ₀])
                    ([x xs] [V Vs] [sₓ (split-values s n)])
            (values (⊔ δσ (ρ@ δρ x) V)
                    (Γ+ (if sₓ (-Γ-with-aliases Γ₁ x sₓ) Γ₁) (-?@ 'defined? (-x x))))))
        (define σ₁ (⊔/m σ₀ δσ))
        
        (match xs-⟦e⟧s
          [(cons (cons xs* ⟦e⟧*) xs-⟦e⟧s*)
           (⊔/ans
             (values δσ ∅ ∅ ∅)
             (((↝.letrec-values l δρ xs* xs-⟦e⟧s* ⟦e⟧) ⟦e⟧*) M σ₁ (-ℒ-with-Γ ℒ Γ₁)))]
          ['()
           (define-values (δσ* ΓWs ΓEs ℐs) (⟦e⟧ M σ (-ℒ-with-Γ ℒ* Γ₁)))
           
           ;;; Erase irrelevant part of path conditions after executing letrec body

           ;; Free variables that outside of `letrec` understands
           (define xs₀ (list->set (hash-keys ρ)))

           (define ΓWs*
             (map/set
              (match-lambda
                [(-ΓW Γ (-W Vs s))
                 (-ΓW (Γ↓ Γ xs₀) (-W Vs (s↓ s xs₀)))])
              ΓWs))
           
           (define ΓEs*
             (map/set
              (match-lambda
                [(-ΓE Γ blm)
                 (-ΓE (Γ↓ Γ xs₀) blm)])
              ΓEs))
           
           (define ℐs*
             (map/set
              (match-lambda
                [(-ℐ (-ℋ ℒ f bnds ℰ) τ)
                 (define Γ* (Γ↓ (-ℒ-cnd ℒ) xs₀))
                 (define f* (s↓ f xs₀))
                 (define bnds*
                   (for/list : (Listof (Pairof Symbol -s)) ([bnd bnds])
                     (match-define (cons x s) bnd)
                     (cons x (s↓ s xs₀))))
                 (-ℐ (-ℋ (-ℒ-with-Γ ℒ Γ*) f* bnds* ℰ) τ)])
              ℐs))
           
           (values (⊔/m δσ δσ*) ΓWs* ΓEs* ℐs*)]))))
   (⟦eₓ⟧ M σ ℒ*)))

(: ↝.set! : Symbol → -⟦ℰ⟧)
(define (((↝.set! x) ⟦e⟧) M σ ℒ)
  (apply/values
   (acc
    σ
    (λ (ℰ) (-ℰ.set! x ℰ))
    (λ (σ* Γ* W)
      (match-define (-W Vs s) W)
      (with-guarded-arity 1 ('TODO Γ* Vs)
        (match-define (list V) Vs)
        (define α (ρ@ (-ℒ-env ℒ) x))
        (values (⊔ ⊥σ α V) {set (-ΓW Γ* -Void/W)} ∅ ∅))))
   (⟦e⟧ M σ ℒ)))

(: ↝.μ/c : Mon-Party Integer → -⟦ℰ⟧)
(define (((↝.μ/c l x) ⟦c⟧) M σ ℒ)
  (apply/values
   (acc
    σ
    (λ (ℰ) (-ℰ.μ/c l x ℰ))
    (λ (σ* Γ* W)
      (with-guarded-arity 1 (l Γ* (-W-Vs W))
        (values ⊥σ {set (-ΓW Γ* W)} ∅ ∅))))
   (⟦c⟧ M σ ℒ)))

(: ↝.-->i : (Listof -W¹) (Listof -⟦e⟧) -W¹ Integer → -⟦ℰ⟧)
(define (((↝.-->i Ws ⟦c⟧s Mk-D ℓ) ⟦e⟧) M σ ℒ)
  (apply/values
   (acc
    σ
    (λ (ℰ) (-ℰ.-->i Ws ℰ ⟦c⟧s Mk-D ℓ))
    (λ (σ* Γ* W)
      (match-define (-W Vs s) W)
      (with-guarded-arity 1 ('TODO Γ* Vs)
        (match-define (list V) Vs)
        (define Ws* (cons (-W¹ V s) Ws))
        (define ℒ* (-ℒ-with-Γ ℒ Γ*))
        (match ⟦c⟧s
          [(cons ⟦c⟧ ⟦c⟧s*)
           (((↝.-->i Ws* ⟦c⟧s* Mk-D ℓ) ⟦c⟧) M σ* ℒ*)]
          ['()
           (mk-=>i ℒ* Ws* Mk-D ℓ)]))))
   (⟦e⟧ M σ ℒ)))

(: mk-=>i : -ℒ (Listof -W¹) -W¹ -ℓ → (Values -Δσ (℘ -ΓW) (℘ -ΓE) (℘ -ℐ)))
;; Given *reversed* list of domains and range-maker, create indy contract
(define (mk-=>i ℒ Ws Mk-D ℓ)
  (match-define (-ℒ _ Γ 𝒞) ℒ)
  (define-values (δσ αs cs) ; `αs` and `cs` reverses `Ws`, which is reversed
    (for/fold ([δσ : -Δσ ⊥σ] [αs : (Listof -α.dom) '()] [cs : (Listof -s) '()])
              ([(W i) (in-indexed Ws)])
      (match-define (-W¹ C c) W)
      (define α (-α.dom ℓ 𝒞 (assert i exact-nonnegative-integer?)))
      (values (⊔ δσ α C) (cons α αs) (cons c cs))))
  (match-define (-W¹ D d) Mk-D)
  (define C (-=>i αs (assert D -Clo?)))
  (define c (-?->i cs (and d (assert d -λ?))))
  (values δσ {set (-ΓW Γ (-W (list C) c))} ∅ ∅))

(: ↝.havoc : Symbol → -⟦e⟧)
(define ((↝.havoc x) M σ ℒ)
  (define Vs (σ@ σ (ρ@ (-ℒ-env ℒ) x)))
  (error '↝.havoc "TODO"))

(: ↝.struct/c : -struct-info (Listof -W¹) (Listof -⟦e⟧) Integer → -⟦ℰ⟧)
(define (((↝.struct/c si Ws ⟦c⟧s ℓ) ⟦c⟧) M σ ℒ)
  (apply/values
   (acc
    σ
    (λ (ℰ) (-ℰ.struct/c si Ws ℰ ⟦c⟧s ℓ))
    (λ (σ* Γ* W)
      (match-define (-W Vs s) W)
      (with-guarded-arity 1 ('TODO Γ* Vs)
        (match-define (list V) Vs)
        (define Ws* (cons (-W¹ V s) Ws))
        (match ⟦c⟧s
          [(cons ⟦c⟧* ⟦c⟧s*)
           (((↝.struct/c si Ws* ⟦c⟧s* ℓ) ⟦c⟧*) M σ* (-ℒ-with-Γ ℒ Γ*))]
          ['()
           (define 𝒞 (-ℒ-hist ℒ))
           (define-values (δσ αs cs flat?) ; `αs` and `cs` reverse `Ws`, which is reversed
             (for/fold ([δσ : -Δσ ⊥σ]
                        [αs : (Listof -α.struct/c) '()]
                        [cs : (Listof -s) '()]
                        [flat? : Boolean #t])
                       ([(W i) (in-indexed Ws*)])
               (match-define (-W¹ C c) W)
               (define α (-α.struct/c ℓ 𝒞 (assert i exact-nonnegative-integer?)))
               (values (⊔ δσ α C) (cons α αs) (cons c cs) (and flat? (C-flat? C)))))
           (define V (-St/C flat? si αs))
           (values δσ {set (-ΓW Γ* (-W (list V) (-?struct/c si cs)))} ∅ ∅)]))))
   (⟦c⟧ M σ ℒ)))



