#lang typed/racket/base

(provide ev ev* co co* ⇓ₚ ⇓ₘₛ ⇓ₘ ⇓ ⊔³)

(require racket/match
         racket/set
         "../utils/main.rkt"
         "../ast/definition.rkt"
         "../runtime/main.rkt"
         "../proof-relation/main.rkt"
         "continuation.rkt"
         "mon.rkt")

(: ev* : -M -Ξ -σ (℘ -τ) → (Values -ΔM -ΔΞ -Δσ))
(define (ev* M Ξ σ τs)
  (for/fold ([δM : -ΔM ⊥M] [δΞ : -ΔΞ ⊥Ξ] [δσ : -Δσ ⊥σ])
            ([τ τs])
    (ev M Ξ σ τ)))

(: co* : -M -Ξ -σ (℘ -Co) → (Values -ΔM -ΔΞ -Δσ))
(define (co* M Ξ σ Cos)
  (for/fold ([δM : -ΔM ⊥M] [δΞ : -ΔΞ ⊥Ξ] [δσ : -Δσ ⊥σ])
            ([Co Cos])
    (co M Ξ σ Co)))

(: ev : -M -Ξ -σ -τ → (Values -ΔM -ΔΞ -Δσ))
;; Execute check-point `τ`, which is either function block `ℬ` for contract checking `ℳ`
(define (ev M Ξ σ τ)
  (apply/values
   (collect M Ξ τ)
   (match τ
     [(-ℬ ⟦e⟧ ℒ) (⟦e⟧ M σ ℒ)]
     [(-ℳ l³ W-C W-V ℒ) ((mon l³ W-C W-V) M σ ℒ)])))

(: co : -M -Ξ -σ -Co → (Values -ΔM -ΔΞ -Δσ))
;; Resume computation `ℋ[A]`, propagating errors and plugging values into hole.
(define (co M Ξ σ Co)
  (match-define (-Co (-ℛ τ₀ ℋ₀) τ As) Co)
  (match-define (-ℋ ℒ₀ f bnds ℰ) ℋ₀)
  ;; Note: in general, `ℒ₀` can be more "updated" than in `τ₀`, because of e.g. `let`

  ;; Propagate errors and plug values into hole
  (define-values (ΓWs ΓEs)
    (let ()
      ; TODO: use path-conditions from caller+callee to eliminate spurious returns
      (define args (map (inst cdr Symbol -s) bnds))
      (define fargs (apply -?@ f args))
      (define Γ₀ (-ℒ-cnd ℒ₀))
      (for/fold ([ΓWs : (℘ -ΓW) ∅] [ΓEs : (℘ -ΓE) ∅])
                ([A As])
        (define Γ₀* (-Γ-plus-γ Γ₀ (-γ τ f bnds)))
        (match A
          [(-ΓW Γ (-W Vs s))
           (values (set-add ΓWs (-ΓW Γ₀* (-W Vs (and s fargs)))) ΓEs)]
          [(-ΓE Γ blm)
           (values ΓWs (set-add ΓEs (-ΓE Γ₀* blm)))]))))
  
  (define-values (δσ* ΓWs* ΓEs* ℐs*) ((ℰ⟦_⟧ ℰ ΓWs) M σ ℒ₀))
  (apply/values (collect M Ξ τ₀) (values δσ* ΓWs* (∪ ΓEs ΓEs*) ℐs*)))

(: ⇓ₚ : (Listof -module) -e → -⟦e⟧)
;; Compile list of modules and top-level expression into computation that
;; runs modules and the top level expression and returns top-level expression's result
(define (⇓ₚ ms e)
  (define ⟦e⟧ (⇓ '† e))
  (match (map ⇓ₘ ms)
    ['() ⟦e⟧]
    [(cons ⟦m⟧ ⟦m⟧s) ((↝.begin (append ⟦m⟧s (list ⟦e⟧))) ⟦m⟧)]))

(: ⇓ₘₛ : (Listof -module) → -⟦e⟧)
;; Compile list of modules into computation that runs modules and return
;; last module's last expression's result
(define (⇓ₘₛ ms)
  (match (map ⇓ₘ ms)
    ['() ⟦void⟧]
    [(cons ⟦m⟧ ⟦m⟧s) ((↝.begin ⟦m⟧s) ⟦m⟧)]))

(: ⇓ₘ : -module → -⟦e⟧)
;; Compile module into computation that runs the module and returns its last expression's result
(define (⇓ₘ m)
  (match-define (-module l ds) m)
  
  (: ⇓pc : -provide-spec → -⟦e⟧)
  (define (⇓pc spec)
    (match-define (-p/c-item x c) spec)
    ((↝.dec (-𝒾 x l)) (⇓ l c)))

  (: ⇓d : -module-level-form → -⟦e⟧)
  (define (⇓d d)
    (match d
      [(-define-values xs e)
       (define αs : (Listof -α.def)
         (for/list ([x xs]) (-α.def (-𝒾 x l))))
       ((↝.def l αs) (⇓ l e))]
      [(-provide specs) ((↝.begin (map ⇓pc specs)) ⟦void⟧)]
      [(? -e? e) (⇓ l e)]
      [_
       (printf "⇓d: ignore ~a~n" (show-module-level-form d))
       ⟦void⟧]))

  (match (map ⇓d ds)
    ['() ⟦void⟧]
    [(cons ⟦d⟧ ⟦d⟧s) ((↝.begin ⟦d⟧s) ⟦d⟧)]))

(: ⇓ : Mon-Party -e → -⟦e⟧)
;; Compile expresion to computation
(define (⇓ l e)

  (: ↓ : -e → -⟦e⟧)
  (define (↓ e) (⇓ l e))
  
  (remember-e!
   (match e
     [(-λ xs e*)
      (define ⟦e*⟧ (↓ e*))
      (λ (M σ ℒ)
        (match-define (-ℒ ρ Γ _) ℒ)
        (values ⊥σ {set (-ΓW Γ (-W (list (-Clo xs ⟦e*⟧ ρ Γ)) e))} ∅ ∅))]
     [(-case-λ body) (error '⇓ "TODO: case-λ")]
     [(? -prim? p) (⇓ₚᵣₘ p)]
     [(-• i)
      (define W (-W -●/Vs e))
      (λ (M σ ℒ)
        (values ⊥σ {set (-ΓW (-ℒ-cnd ℒ) W)} ∅ ∅))]
     [(-x x)
      (λ (M σ ℒ)
        (match-define (-ℒ ρ Γ 𝒞) ℒ)
        (define s (canonicalize Γ x))
        (define-values (ΓWs ΓEs)
          (for*/fold ([ΓWs : (℘ -ΓW) ∅]
                      [ΓEs : (℘ -ΓE) ∅])
                     ([V (σ@ σ (ρ@ ρ x))]
                      [W (in-value (-W (list V) s))]
                      #:unless (spurious? M σ Γ W))
            (case V
              [(undefined) ; spurious `undefined` should have been eliminated by `spurious?`
               (values
                ΓWs
                (set-add
                 ΓEs
                 (-ΓE Γ (-blm 'TODO 'Λ (list 'defined?) (list 'undefined)))))]
              [else (values (set-add ΓWs (-ΓW Γ W)) ΓEs)])))
        (values ⊥σ ΓWs ΓEs ∅))]
     [(and ref (-ref (and 𝒾 (-𝒾 x l₀)) ℓ))
      (cond
        ;; same-module referencing returns unwrapped version
        [(equal? l₀ l)
         (define α (-α.def 𝒾))
         (λ (M σ ℒ)
           (define Γ (-ℒ-cnd ℒ))
           (define ΓWs
             (for/set: : (℘ -ΓW) ([V (σ@ σ α)])
               (define s (if (-o? V) V ref))
               (-ΓW Γ (-W (list V) s))))
           (values ⊥σ ΓWs ∅ ∅))]
        ;; cross-module referencing returns wrapped version
        ;;  and (hack) supply the negative context
        [else
         (define α (-α.wrp 𝒾))
         (λ (M σ ℒ)
           (define Γ (-ℒ-cnd ℒ))
           (define ΓWs
             (for/set: : (℘ -ΓW) ([V (σ@ σ α)])
               (define s (if (-o? V) V ref))
               (-ΓW Γ (-W (list (supply-negative-party l V)) s))))
           (values ⊥σ ΓWs ∅ ∅))])]
     [(-@ f xs ℓ)
      ((↝.@ l ℓ '() (map ↓ xs)) (↓ f))]
     [(-if e₀ e₁ e₂)
      ((↝.if l (↓ e₁) (↓ e₂)) (↓ e₀))]
     [(-wcm k v b)
      (error '⇓ "TODO: wcm")]
     [(-begin es)
      (match es
        [(cons e* es*) ((↝.begin (map ↓ es*)) (↓ e*))]
        ['() ⟦void⟧])]
     [(-begin0 e₀ es)
      ((↝.begin0.v (map ↓ es)) (↓ e₀))]
     [(-quote q)
      (cond
        [(Base? q)
         (define b (-b q))
         (λ (M σ ℒ)
           (values ⊥σ {set (-ΓW (-ℒ-cnd ℒ) (-W (list b) b))} ∅ ∅))]
        [else (error '⇓ "TODO: (quote ~a)" q)])]
     [(-let-values xs-es e)
      (define xs-⟦e⟧s
        (for/list : (Listof (Pairof (Listof Symbol) -⟦e⟧)) ([xs-e xs-es])
          (match-define (cons xs eₓ) xs-e)
          (cons xs (↓ eₓ))))
      (define ⟦e⟧ (↓ e))
      (match xs-⟦e⟧s 
        ['() ⟦e⟧]
        [(cons (cons xs₀ ⟦e⟧₀) xs-⟦eₓ⟧s*)
         ((↝.let-values l '() xs₀ xs-⟦eₓ⟧s* ⟦e⟧) ⟦e⟧₀)])]
     [(-letrec-values xs-es e)
      (define xs-⟦e⟧s
        (for/list : (Listof (Pairof (Listof Symbol) -⟦e⟧)) ([xs-e xs-es])
          (match-define (cons xs eₓ) xs-e)
          (cons xs (↓ eₓ))))
      (define ⟦e⟧ (↓ e))
      (match xs-⟦e⟧s
        ['() ⟦e⟧]
        [(cons (cons xs₀ ⟦e⟧₀) xs-⟦e⟧s*)
         (λ (M σ ℒ)
           (define 𝒞 (-ℒ-hist ℒ))
           (define-values (δσ δρ)
             (for*/fold ([δσ : -Δσ ⊥σ] [δρ : -Δρ ⊥ρ])
                        ([xs-⟦e⟧ xs-⟦e⟧s] [x (car xs-⟦e⟧)])
               (define α (-α.x x 𝒞))
               (values (⊔ δσ α 'undefined)
                       (hash-set δρ x α))))
           (define σ* (⊔/m σ δσ))
           (((↝.letrec-values l δρ xs₀ xs-⟦e⟧s* ⟦e⟧) ⟦e⟧₀) M σ* ℒ))])]
     [(-set! x e*) ((↝.set! x) (↓ e*))]
     [(-@-havoc (-x x)) (↝.havoc x)]
     [(-amb es)
      (define ⟦e⟧s (set-map es ↓))
      (λ (M σ ℒ)
        (for*/ans ([⟦e⟧ ⟦e⟧s]) (⟦e⟧ M σ ℒ)))]
     [(-μ/c x c) ((↝.μ/c l x) (↓ c))]
     [(-->i cs (and mk-d (-λ xs d)) l)
      (define ⟦d⟧ (↓ d))
      (match (map ↓ cs)
        ['()
         (define c (-?->i '() mk-d))
         (λ (M σ ℒ)
           (match-define (-ℒ ρ Γ _) ℒ)
           (define Mk-D (-W¹ (-Clo xs ⟦d⟧ ρ Γ) mk-d))
           (mk-=>i ℒ '() Mk-D l))]
        [(cons ⟦c⟧ ⟦c⟧s*)
         (λ (M σ ℒ)
           (match-define (-ℒ ρ Γ _) ℒ)
           (define Mk-D (-W¹ (-Clo xs ⟦d⟧ ρ Γ) mk-d))
           (((↝.-->i '() ⟦c⟧s* Mk-D l) ⟦c⟧) M σ ℒ))])]
     [(-x/c x)
      (λ (M σ ℒ)
        (define Γ (-ℒ-cnd ℒ))
        (define ΓWs
          (for/set: : (℘ -ΓW) ([V (σ@ σ (-α.x/c x))])
            (-ΓW Γ (-W (list V) e))))
        (values ⊥σ ΓWs ∅ ∅))]
     [(-struct/c si cs l)
      (match cs
        ['()
         (λ (M σ ℒ)
           (define V (-St/C #t si '()))
           (define W (-W (list V) e))
           (values ⊥σ {set (-ΓW (-ℒ-cnd ℒ) W)} ∅ ∅))]
        [(cons c cs*)
         ((↝.struct/c si '() (map ↓ cs*) l) (↓ c))])])
   e))

(: ℰ⟦_⟧ : -ℰ (℘ -ΓW) → -⟦e⟧)
;; Plug answers `ΓWs` into hole `ℰ` and resume computation
;; Stacks `ℰ` are finite, but I can't "compile" them ahead of time because they depend on
;; "run-time" `V`. Using functions instead of flat values to represent `ℰ` may generate
;; infinitely many equivalent but distinct (Racket-level) functions.
;; Memoization might help, but I doubt it speeds up anything.
;; So I'll keep things simple for now.
(define (ℰ⟦_⟧ ℰ ΓWs)
  (let go : -⟦e⟧ ([ℰ : -ℰ ℰ])
    (match ℰ
      ;; Hacky forms
      [(-ℰ.def m xs ℰ*) ((↝.def m xs) (go ℰ*))]
      [(-ℰ.dec id ℰ*) ((↝.dec id) (go ℰ*))]
      ;; Regular forms
      ['□ (λ _ (values ⊥σ ΓWs ∅ ∅))]
      [(-ℰ.if l ℰ* ⟦e₁⟧ ⟦e₂⟧) ((↝.if l ⟦e₁⟧ ⟦e₂⟧) (go ℰ*))]
      [(-ℰ.@ l ℓ WVs ℰ* ⟦e⟧s) ((↝.@ l ℓ WVs ⟦e⟧s) (go ℰ*))]
      [(-ℰ.begin ℰ* ⟦e⟧s) ((↝.begin ⟦e⟧s) (go ℰ*))]
      [(-ℰ.begin0.v ℰ* ⟦e⟧s) ((↝.begin0.v ⟦e⟧s) (go ℰ*))]
      [(-ℰ.begin0.e W ℰ* ⟦e⟧s) ((↝.begin0.e W ⟦e⟧s) (go ℰ*))]
      [(-ℰ.let-values l xs-Ws (cons xs ℰ*) xs-⟦e⟧s ⟦e⟧)
       ((↝.let-values l xs-Ws xs xs-⟦e⟧s ⟦e⟧) (go ℰ*))]
      [(-ℰ.letrec-values l δρ (cons xs ℰ*) xs-⟦e⟧s ⟦e⟧)
       ((↝.letrec-values l δρ xs xs-⟦e⟧s ⟦e⟧) (go ℰ*))]
      [(-ℰ.set! x ℰ*) ((↝.set! x) (go ℰ*))]
      [(-ℰ.μ/c l x ℰ*) ((↝.μ/c l x) (go ℰ*))]
      [(-ℰ.-->i Cs ℰ* ⟦c⟧s ⟦mk-d⟧ l)
       ((↝.-->i Cs ⟦c⟧s ⟦mk-d⟧ l) (go ℰ*))]
      [(-ℰ.struct/c si Cs ℰ* ⟦c⟧s l)
       ((↝.struct/c si Cs ⟦c⟧s l) (go ℰ*))])))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; Helpers
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-syntax-rule (⊔³ x y)
  (let-values ([(m₁ m₂ m₃) x]
               [(n₁ n₂ n₃) y])
    (values (⊔/m m₁ n₁) (⊔/m m₂ n₂) (⊔/m m₃ n₃))))

(: collect : -M -Ξ -τ → -Δσ (℘ -ΓW) (℘ -ΓE) (℘ -ℐ) → (Values -ΔM -ΔΞ -Δσ))
;; Collect evaluation results into store deltas
(define ((collect M Ξ τ) δσ ΓWs ΓEs ℐs)
  
  (define δM : -ΔM
    (let* ([As (M@ M τ)]
           [δ-As (-- (∪ ΓWs ΓEs) As)])
      (if (set-empty? δ-As) ⊥M (hash τ δ-As))))
  
  (define δΞ
    (for*/fold ([δΞ : -ΔΞ ⊥Ξ])
               ([ℐ ℐs]
                [ℋ  (in-value (-ℐ-hole ℐ))]
                [τ* (in-value (-ℐ-target ℐ))]
                [ℛ  (in-value (-ℛ τ ℋ))]
                #:unless (m∋ Ξ τ* ℛ))
      (⊔ δΞ τ* ℛ)))
  
  (values δM δΞ δσ))

;; Memoized because `Λ` needs a ridiculous number of these

(define ⇓ₚᵣₘ : (-prim → -⟦e⟧) 
  (let ([meq : (HashTable Any -⟦e⟧) (make-hasheq)] ; `eq` doesn't work for String but ok
        [m   : (HashTable Any -⟦e⟧) (make-hash  )])
    
    (define (ret-p [p : -prim]) : -⟦e⟧
      (define W (-W (list p) p))
      (λ (M σ ℒ)
        (values ⊥σ {set (-ΓW (-ℒ-cnd ℒ) W)} ∅ ∅)))
    
    (match-lambda
      [(? symbol? o)  (hash-ref! meq o (λ () (ret-p o)))]
      [(and B (-b b)) (hash-ref! meq b (λ () (ret-p B)))]
      [p              (hash-ref! m   p (λ () (ret-p p)))])))

(define ⟦void⟧ (⇓ₚᵣₘ -void))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; Testing
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (ev₁ [e : -e])
  (define-values (δM δΞ δσ) (ev ⊥M ⊥Ξ ⊥σ (-ℬ (⇓ 'test e) ℒ∅)))
  (values (show-M δM) (show-Ξ δΞ) (show-σ δσ)))


