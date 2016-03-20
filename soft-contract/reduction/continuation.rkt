#lang typed/racket/base

;; Each function `↝._` implements semantics of corresponding continuation frame,
;; returning ⟦e⟧→⟦e⟧.
;; This is factored out because it's used in both compilation `⇓` and resumption `ℰ⟦_⟧`.

(provide (all-defined-out))

(require
 racket/match racket/set racket/list
 "../utils/main.rkt" "../ast/main.rkt" "../runtime/main.rkt" "../proof-relation/main.rkt" "../delta.rkt")

(: ↝.modules : (Listof -⟦e⟧) -⟦e⟧ → -⟦ℰ⟧)
(define ((↝.modules ⟦m⟧s ⟦e⟧) ⟦e⟧ᵢ)
  (define ⟦e⟧ᵣ
    (match ⟦m⟧s
      ['() ⟦e⟧]
      [(cons ⟦m⟧ ⟦m⟧s*) ((↝.modules ⟦m⟧s* ⟦e⟧) ⟦m⟧)]))
  
  (λ (M σ ℬ)
    (apply/values
     (acc
      σ
      (λ (ℰ) (-ℰₚ.modules ℰ ⟦m⟧s ⟦e⟧))
      (λ (σ* Γ* W) (⟦e⟧ᵣ M σ* (-ℬ-with-Γ ℬ Γ*))))
     (⟦e⟧ᵢ M σ ℬ))))


(: ↝.def : Adhoc-Module-Path (Listof Symbol) → -⟦ℰ⟧)
;; Define top-level `xs` to be values from `⟦e⟧`
(define (((↝.def l xs) ⟦e⟧) M σ ℬ)
  (apply/values
   (acc
    σ
    (λ (ℰ) (-ℰ.def l xs ℰ))
    (λ (σ* Γ* W)
      (define Vs (-W-Vs W))
      (with-guarded-arity (length xs) (l Γ* Vs)
        (define δσ
          (for/fold ([δσ : -Δσ ⊥σ]) ([x xs] [V Vs])
            (define α (-α.def (-𝒾 x l)))
            (⊔ δσ α V)))
        (values δσ {set (-ΓW Γ* -Void/W)} ∅ ∅))))
    (⟦e⟧ M σ ℬ)))

(: ↝.dec : -𝒾 → -⟦ℰ⟧)
;; Make `⟦c⟧`. the contract for `𝒾`.
(define (((↝.dec 𝒾) ⟦c⟧) M σ ℬ)
  (apply/values
   (acc
    σ
    (λ (ℰ) (-ℰ.dec 𝒾 ℰ))
    (λ (σ* Γ* W)
      (define Vs (-W-Vs W))
      (define l (-𝒾-ctx 𝒾))
      (with-guarded-arity 1 (l Γ* Vs)
        (match-define (list C) Vs)
        (define ℬ* (-ℬ-with-Γ ℬ Γ*))
        (for*/ans ([V (σ@ σ (-α.def 𝒾))])
          (mon (Mon-Info l 'dummy l) M σ ℬ* C V)))))
   (⟦c⟧ M σ ℬ)))

(: ↝.if : Mon-Party -⟦e⟧ -⟦e⟧ → -⟦ℰ⟧)
(define (((↝.if l ⟦e₁⟧ ⟦e₂⟧) ⟦e₀⟧) M σ ℬ)
  (apply/values
   (acc
    σ
    (λ (ℰ) (-ℰ.if l ℰ ⟦e₁⟧ ⟦e₂⟧))
    (λ (σ* Γ* W)
      (match-define (-W Vs s) W)
      (with-guarded-arity 1 (l Γ* Vs)
        (match-define (list V) Vs)
        (define-values (Γ₁ Γ₂) (Γ+/-V M σ* Γ* V s))
        (⊔/ans (with-Γ Γ₁ (⟦e₁⟧ M σ* (-ℬ-with-Γ ℬ Γ₁)))
               (with-Γ Γ₂ (⟦e₂⟧ M σ* (-ℬ-with-Γ ℬ Γ₂)))))))
    (⟦e₀⟧ M σ ℬ)))

(: ↝.@ : Mon-Party -ℓ (Listof -W¹) (Listof -⟦e⟧) → -⟦ℰ⟧)
(define (((↝.@ l ℓ Ws ⟦e⟧s) ⟦e⟧) M σ ℬ)
  (apply/values
   (acc
    σ
    (λ (ℰ) (-ℰ.@ l ℓ Ws ℰ ⟦e⟧s))
    (λ (σ* Γ* W)
      (match-define (-W Vs s) W)
      (with-guarded-arity 1 (l Γ* Vs)
        (match-define (list V) Vs)
        (define Ws* (cons (-W¹ V s) Ws))
        (define ℬ* (-ℬ-with-Γ ℬ Γ*))
        (match ⟦e⟧s ; TODO: move this dispatch out?
          ['()
           (match-define (cons Wₕ Wₓs) (reverse Ws*))
           (ap l ℓ M σ* ℬ* Wₕ Wₓs)]
          [(cons ⟦e⟧* ⟦e⟧s*)
           (((↝.@ l ℓ Ws* ⟦e⟧s*) ⟦e⟧*) M σ* ℬ*)]))))
   (⟦e⟧ M σ ℬ)))

(: ↝.begin : (Listof -⟦e⟧) → -⟦ℰ⟧)
(define ((↝.begin ⟦e⟧s) ⟦e⟧)
  (match ⟦e⟧s
    ['() ⟦e⟧]
    [(cons ⟦e⟧* ⟦e⟧s*)
     (define ⟦eᵣ⟧ ((↝.begin ⟦e⟧s*) ⟦e⟧*))
     (λ (M σ ℬ)
       (apply/values
        (acc
         σ
         (λ (ℰ) (-ℰ.begin ℰ ⟦e⟧s))
         (λ (σ* Γ* _) (⟦eᵣ⟧ M σ* (-ℬ-with-Γ ℬ Γ*))))
        (⟦e⟧ M σ ℬ)))]))

(: ↝.begin0.v : (Listof -⟦e⟧) → -⟦ℰ⟧)
;; Waiting on `⟦e⟧` to be the returned value for `begin0`
(define ((↝.begin0.v ⟦e⟧s) ⟦e⟧)
  (match ⟦e⟧s
    ['() ⟦e⟧]
    [(cons ⟦e⟧* ⟦e⟧s*)
     (λ (M σ ℬ)
       (apply/values
        (acc
         σ
         (λ (ℰ) (-ℰ.begin0.v ℰ ⟦e⟧s))
         (λ (σ* Γ* W)
           (define ⟦eᵣ⟧ ((↝.begin0.e W ⟦e⟧s*) ⟦e⟧*))
           (⟦eᵣ⟧ M σ* (-ℬ-with-Γ ℬ Γ*))))
        (⟦e⟧ M σ ℬ)))]))

(: ↝.begin0.e : -W (Listof -⟦e⟧) → -⟦ℰ⟧)
(define ((↝.begin0.e W ⟦e⟧s) ⟦e⟧)
  (match ⟦e⟧s
    ['()
     (λ (M σ ℬ)
       (values ⊥σ {set (-ΓW (-ℬ-cnd ℬ) W)} ∅ ∅))]
    [(cons ⟦e⟧* ⟦e⟧s*)
     (define ⟦e⟧ᵣ ((↝.begin0.e W ⟦e⟧s*) ⟦e⟧*))
     (λ (M σ ℬ)
       (apply/values
        (acc
         σ
         (λ (ℰ) (-ℰ.begin0.e W ℰ ⟦e⟧s))
         (λ (σ* Γ* _)
           (⟦e⟧ᵣ M σ* (-ℬ-with-Γ ℬ Γ*))))
        (⟦e⟧ M σ ℬ)))]))

(: ↝.let-values : Mon-Party
                  (Listof (Pairof Symbol -W¹))
                  (Listof Symbol)
                  (Listof (Pairof (Listof Symbol) -⟦e⟧))
                  -⟦e⟧
                  → -⟦ℰ⟧)
(define (((↝.let-values l x-Ws xs xs-⟦e⟧s ⟦e⟧) ⟦eₓ⟧) M σ ℬ)
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
           (match-define (-ℬ ⟦e⟧₀ ρ _ 𝒞) ℬ)
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
                  (⟦e⟧ M σ** (-ℬ ⟦e⟧₀ ρ* Γ** 𝒞)))]
          [(cons (cons xs* ⟦e⟧*) xs-⟦e⟧s*)
           (((↝.let-values l x-Ws* xs* xs-⟦e⟧s* ⟦e⟧) ⟦e⟧*) M σ* (-ℬ-with-Γ ℬ Γ*))]
          ))))
   (⟦eₓ⟧ M σ ℬ)))

(: ↝.letrec-values : Mon-Party
                     -Δρ
                     (Listof Symbol)
                     (Listof (Pairof (Listof Symbol) -⟦e⟧))
                     -⟦e⟧
                     → -⟦ℰ⟧)
(define (((↝.letrec-values l δρ xs xs-⟦e⟧s ⟦e⟧) ⟦eₓ⟧) M σ ℬ)
  ;; FIXME: inefficient. `ρ*` is recomputed many times
  (define ρ (-ℬ-env ℬ))
  (define ℬ* (-ℬ-with-ρ ℬ (ρ++ ρ δρ)))
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
             (((↝.letrec-values l δρ xs* xs-⟦e⟧s* ⟦e⟧) ⟦e⟧*) M σ₁ (-ℬ-with-Γ ℬ Γ₁)))]
          ['()
           (define-values (δσ* ΓWs ΓEs ℐs) (⟦e⟧ M σ (-ℬ-with-Γ ℬ* Γ₁)))
           
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
                [(-ℐ (-ℋ ρ Γ f bnds ℰ) ℬ)
                 (define Γ* (Γ↓ Γ xs₀))
                 (define f* (s↓ f xs₀))
                 (define bnds*
                   (for/list : (Listof (Pairof Symbol -s)) ([bnd bnds])
                     (match-define (cons x s) bnd)
                     (cons x (s↓ s xs₀))))
                 (-ℐ (-ℋ ρ Γ* f* bnds* ℰ) ℬ)])
              ℐs))
           
           (values (⊔/m δσ δσ*) ΓWs* ΓEs* ℐs*)]))))
   (⟦eₓ⟧ M σ ℬ*)))

(: ↝.set! : Symbol → -⟦ℰ⟧)
(define (((↝.set! x) ⟦e⟧) M σ ℬ)
  (apply/values
   (acc
    σ
    (λ (ℰ) (-ℰ.set! x ℰ))
    (λ (σ* Γ* W)
      (match-define (-W Vs s) W)
      (with-guarded-arity 1 ('TODO Γ* Vs)
        (match-define (list V) Vs)
        (define α (ρ@ (-ℬ-env ℬ) x))
        (values (⊔ ⊥σ α V) {set (-ΓW Γ* -Void/W)} ∅ ∅))))
   (⟦e⟧ M σ ℬ)))

(: ↝.μ/c : Mon-Party Integer → -⟦ℰ⟧)
(define (((↝.μ/c l x) ⟦c⟧) M σ ℬ)
  (apply/values
   (acc
    σ
    (λ (ℰ) (-ℰ.μ/c l x ℰ))
    (λ (σ* Γ* W)
      (with-guarded-arity 1 (l Γ* (-W-Vs W))
        (values ⊥σ {set (-ΓW Γ* W)} ∅ ∅))))
   (⟦c⟧ M σ ℬ)))

(: ↝.-->i : (Listof -W¹) (Listof -⟦e⟧) -W¹ Integer → -⟦ℰ⟧)
(define (((↝.-->i Ws ⟦c⟧s Mk-D ℓ) ⟦e⟧) M σ ℬ)
  (apply/values
   (acc
    σ
    (λ (ℰ) (-ℰ.-->i Ws ℰ ⟦c⟧s Mk-D ℓ))
    (λ (σ* Γ* W)
      (match-define (-W Vs s) W)
      (with-guarded-arity 1 ('TODO Γ* Vs)
        (match-define (list V) Vs)
        (define Ws* (cons (-W¹ V s) Ws))
        (define ℬ* (-ℬ-with-Γ ℬ Γ*))
        (match ⟦c⟧s
          [(cons ⟦c⟧ ⟦c⟧s*)
           (((↝.-->i Ws* ⟦c⟧s* Mk-D ℓ) ⟦c⟧) M σ* ℬ*)]
          ['()
           (mk-=>i ℬ* Ws* Mk-D ℓ)]))))
   (⟦e⟧ M σ ℬ)))

(: mk-=>i : -ℬ (Listof -W¹) -W¹ -ℓ → (Values -Δσ (℘ -ΓW) (℘ -ΓE) (℘ -ℐ)))
;; Given *reversed* list of domains and range-maker, create indy contract
(define (mk-=>i ℬ Ws Mk-D ℓ)
  (match-define (-ℬ _ _ Γ 𝒞) ℬ)
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
(define ((↝.havoc x) M σ ℬ)
  (define Vs (σ@ σ (ρ@ (-ℬ-env ℬ) x)))
  (error '↝.havoc "TODO"))

(: ↝.struct/c : -struct-info (Listof -W¹) (Listof -⟦e⟧) Integer → -⟦ℰ⟧)
(define (((↝.struct/c si Ws ⟦c⟧s ℓ) ⟦c⟧) M σ ℬ)
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
           (((↝.struct/c si Ws* ⟦c⟧s* ℓ) ⟦c⟧*) M σ* (-ℬ-with-Γ ℬ Γ*))]
          ['()
           (define 𝒞 (-ℬ-hist ℬ))
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
   (⟦c⟧ M σ ℬ)))

(: ap : Mon-Party -ℓ -M -σ -ℬ -W¹ (Listof -W¹) → (Values -Δσ (℘ -ΓW) (℘ -ΓE) (℘ -ℐ)))
;; Apply value `Wₕ` to arguments `Wₓ`s, returning store widening, answers, and suspended computation
(define (ap l ℓ M σ ℬ₀ Wₕ Wₓs)
  (match-define (-ℬ ⟦e⟧₀ ρ₀ Γ₀ 𝒞₀) ℬ₀)
  (match-define (-W¹ Vₕ sₕ) Wₕ)
  (define-values (Vₓs sₓs) (unzip-by -W¹-V -W¹-s Wₓs))
  (define sₐ (apply -?@ sₕ sₓs))

  ;; TODO: guard against wrong arity

  (: ap/δ : Symbol → (Values -Δσ (℘ -ΓW) (℘ -ΓE) (℘ -ℐ)))
  ;; Apply primitive
  (define (ap/δ o)
    (define-values (δσ A*) (δ 𝒞₀ ℓ M σ Γ₀ o Wₓs))
    (cond [(list? A*)
           (values δσ {set (-ΓW Γ₀ (-W A* sₐ))} ∅ ∅)]
          ;; Rely on `δ` giving no error
          [else (⊥ans)]))

  (: ap/β : -formals -⟦e⟧ -ρ -Γ → (Values -Δσ (℘ -ΓW) (℘ -ΓE) (℘ -ℐ)))
  ;; Apply λ abstraction
  (define (ap/β xs ⟦e⟧ ρ Γ₁)
    (define 𝒞₁ (𝒞+ 𝒞₀ (cons ⟦e⟧ ℓ)))
    (define-values (δσ ρ₁)
      (match xs
        [(? list? xs)
         (for/fold ([δσ : -Δσ ⊥σ] [ρ₁ : -ρ ρ])
                   ([x xs] [V Vₓs])
           (define α (-α.x x 𝒞₁))
           (values (⊔ δσ α V) (ρ+ ρ₁ x α)))]
        [_ (error 'ap/β "TODO: varargs")]))
    (define bnds (map (inst cons Symbol -s) xs sₓs))
    (define ℬ₁ (-ℬ ⟦e⟧ ρ₁ Γ₁ 𝒞₁))
    (values δσ ∅ ∅ {set (-ℐ (-ℋ ρ₀ Γ₀ sₕ bnds '□) ℬ₁)}))
  
  (match Vₕ
    [(-Clo xs ⟦e⟧ ρ Γ) (ap/β xs ⟦e⟧ ρ Γ)]
    [(? symbol? o) (ap/δ o)]
    [(-Ar _ _ l³)
     (error 'ap "Arr")]
    [(-And/C #t α₁ α₂)
     (error 'ap "And/C")]
    [(-Or/C #t α₁ α₂)
     (error 'ap "Or/C")]
    [(-Not/C α)
     (error 'ap "Not/C")]
    [(-St/C #t si αs)
     (error 'ap "St/C")]
    [(-●) ; FIXME havoc
     (printf "ap: ●~n")
     (values ⊥σ {set (-ΓW Γ₀ (-W -●/Vs sₐ))} ∅ ∅)]
    [_ (values ⊥σ ∅ {set (-ΓE Γ₀ (-blm l 'Λ (list 'procedure?) (list Vₕ)))} ∅)]))

(: mon : Mon-Info -M -σ -ℬ -V -V → (Values -Δσ (℘ -ΓW) (℘ -ΓE) (℘ -ℐ)))
(define (mon l³ M σ ℬ C V)
  (error 'mon "TODO"))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; Helpers
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(: acc : -σ (-ℰ → -ℰ) (-σ -Γ -W → (Values -Δσ (℘ -ΓW) (℘ -ΓE) (℘ -ℐ)))
        → -Δσ (℘ -ΓW) (℘ -ΓE) (℘ -ℐ)
        → (Values -Δσ (℘ -ΓW) (℘ -ΓE) (℘ -ℐ)))
;; Bind-ish. Takes care of store widening.
;; Caller takes care of stack accumulation and what to do with result.
(define ((acc σ f comp) δσ ΓWs ΓEs ℐs)
  (define ℐs*
    (map/set
     (match-lambda
       [(-ℐ (-ℋ ρ Γ s 𝒳    ℰ ) ℬ)
        (-ℐ (-ℋ ρ Γ s 𝒳 (f ℰ)) ℬ)])
     ℐs))
  (define σ* (⊔/m σ δσ))
  (for/fold ([δσ : -Δσ δσ] [ΓWs* : (℘ -ΓW) ∅] [ΓEs* : (℘ -ΓE) ΓEs] [ℐs* : (℘ -ℐ) ℐs*])
            ([ΓW ΓWs])
    (match-define (-ΓW Γ* W) ΓW)
    (define-values (δσ+ ΓWs+ ΓEs+ ℐs+) (comp σ* Γ* W))
    (values (⊔/m δσ δσ+) (∪ ΓWs* ΓWs+) (∪ ΓEs* ΓEs+) (∪ ℐs* ℐs+))))

(define-syntax-rule (with-guarded-arity n* (l Γ Vs) e ...)
  (let ([n n*]
        [m (length Vs)])
    (cond
      [(= n m) e ...]
      [else
       (define Cs (make-list n 'any/c))
       (values ⊥σ ∅ {set (-ΓE Γ (-blm l 'Λ Cs Vs))} ∅)])))
