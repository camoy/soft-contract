#lang typed/racket/base

(provide run-file havoc-file run-e)

(require "../utils/main.rkt"
         "../ast/main.rkt"
         "../parse/main.rkt"
         "../runtime/main.rkt"
         "../proof-relation/main.rkt"
         "compile/kontinuation.rkt"
         "compile/main.rkt"
         "init.rkt"
         racket/set
         racket/match
         (only-in racket/list split-at))

(: run-file : Path-String → (Values (℘ -ΓA) -Σ))
(define (run-file p)
  (define m (file->module p))
  (define-values (σ₁ _) (𝑰 (list m)))
  (run (↓ₘ m) σ₁))

(: havoc-file : Path-String → (Values (℘ -ΓA) -Σ))
(define (havoc-file p)
  (define m (file->module p))
  (define-values (σ₁ e₁) (𝑰 (list m)))
  (run (↓ₚ (list m) e₁) σ₁))

(: run-e : -e → (Values (℘ -ΓA) -Σ))
(define (run-e e)
  (define-values (σ₀ _) (𝑰 '()))
  (run (↓ₑ 'top e) σ₀))

(: run : -⟦e⟧! -σ → (Values (℘ -ΓA) -Σ))
(define (run ⟦e⟧! σ)
  (define Σ (-Σ σ (⊥σₖ) (⊥M)))
  (define seen : (HashTable -ς (List Integer Integer Integer)) (make-hash))
  (define αₖ₀ : -αₖ (-ℬ '() ⟦e⟧! ⊥ρ))

  (define iter : Natural 0)

  (let loop! ([front : (℘ -ς) {set (-ς↑ αₖ₀ ⊤Γ 𝒞∅)}])
    (unless (set-empty? front)

      (begin
        (define num-front (set-count front))
        (define-values (ς↑s ς↓s) (set-partition -ς↑? front))
        (define num-ς↑s (set-count ς↑s))
        (define num-ς↓s (set-count ς↓s))
        (printf "iter ~a: ~a (~a + ~a) ~n" iter num-front num-ς↑s num-ς↓s)

        #;(begin ; verbose

          (begin ; interactive
            (define ςs-list
              (append (set->list ς↑s) (set->list ς↓s)))
            (define ς->i
              (for/hash : (HashTable -ς Integer) ([(ς i) (in-indexed ςs-list)])
                (values ς i))))
          
          (printf " *~n")
          (for ([ς ς↑s])
            (printf "  -[~a]. ~a~n" (hash-ref ς->i ς) (show-ς ς)))
          (printf " *~n")
          (for ([ς ς↓s])
            (printf "  -[~a]. ~a~n" (hash-ref ς->i ς) (show-ς ς)))

          #;(begin ; interactive
              (printf "~nchoose [0-~a|ok|done]: " (sub1 (hash-count ς->i)))
              (match (read)
                [(? exact-integer? i) (set! front (set (list-ref ςs-list i)))]
                ['done (error "DONE")]
                [_ (void)]))
          )
        
        (printf "~n")
        (set! iter (+ 1 iter)))

      (define next
        (for/union : (℘ -ς) ([ς front])
          (match-define (-Σ σ σₖ M) Σ)
          (define vsn : (List Integer Integer Integer)
            (list (-σ-version σ) (VMap-version σₖ) (VMap-version M)))
          (cond
            [(equal? vsn (hash-ref seen ς #f))
             ;(printf "Seen ~a before~n~n" (show-ς ς))
             ∅]
            [else
             ;(printf "Haven't seen ~a before~n~n" (show-ς ς))
             (hash-set! seen ς vsn)
             (↝! ς Σ)])))
      (loop! next)))

  (match-let ([(-Σ σ σₖ M) Σ])
    (values (M@ M αₖ₀) Σ)))

(: ς->αs : -ς↑ → (℘ -α))
(define ς->αs
  (match-lambda
    [(-ς↑ αₖ _ _) (αₖ->αs αₖ)]))

(: αₖ->αs : -αₖ → (℘ -α))
(define αₖ->αs
  (match-lambda
    [(-ℬ _ _ ρ) (ρ->αs ρ)]
    [(-ℳ _ _ _ (-W¹ C _) (-W¹ V _)) (∪ (V->αs C) (V->αs V))]
    [(-ℱ _ _ _ (-W¹ C _) (-W¹ V _)) (∪ (V->αs C) (V->αs V))]))

(: ς->αₖs : -ς↑ → (℘ -αₖ))
(define ς->αₖs
  (match-lambda
    [(-ς↑ _ Γ _) (Γ->αs Γ)]))

(: ↝! : -ς -Σ → (℘ -ς))
;; Perform one "quick-step" on configuration,
;; Producing set of next configurations and store-deltas
(define (↝! ς Σ)
  (with-debugging/off
    ((ςs)
     (match ς
       [(-ς↑ αₖ Γ 𝒞) (↝↑! αₖ Γ 𝒞 Σ)]
       [(-ς↓ αₖ Γ A) (↝↓! αₖ Γ A Σ)]))
    (printf "Stepping ~a: (~a) ~n" (show-ς ς) (set-count ςs))
    (for ([ς ςs])
      (printf "  - ~a~n" (show-ς ς)))
    (printf "~n")))

(: ↝↑! : -αₖ -Γ -𝒞 -Σ → (℘ -ς))
;; Quick-step on "push" state
(define (↝↑! αₖ Γ 𝒞 Σ)
  (define ⟦k⟧ (rt αₖ))
  (match αₖ
    [(-ℬ _ ⟦e⟧! ρ)
     (⟦e⟧! ρ $∅ Γ 𝒞 Σ ⟦k⟧)]
    [(-ℳ _ l³ ℓ W-C W-V)
     (mon l³ $∅ ℓ W-C W-V Γ 𝒞 Σ ⟦k⟧)]
    [(-ℱ _ l ℓ W-C W-V)
     (flat-chk l $∅ ℓ W-C W-V Γ 𝒞 Σ ⟦k⟧)]
    [_
     (error '↝↑ "~a" αₖ)]))

(: ↝↓! : -αₖ -Γ -A -Σ → (℘ -ς))
;; Quick-step on "pop" state
(define (↝↓! αₖ Γₑₑ A Σ)
  (match-define (-Σ _ σₖ M) Σ)
  (for/union : (℘ -ς) ([κ (σₖ@ σₖ αₖ)])
    (match-define (-κ ⟦k⟧ Γₑᵣ 𝒞ₑᵣ sₕ sₓs) κ)
    (define fargs (apply -?@ sₕ sₓs))
    (match A
      [(-W Vs sₐ)
       (define γ (-γ αₖ #f sₕ sₓs))
       (define Γₑᵣ* (-Γ-plus-γ Γₑᵣ γ))
       (define Γₑᵣ**
         ; It's useful to check for feasibility of a strong path-condition
         ; before forgetting and keeping the path-condition address
         ; as an approximation
         ; TODO generalize
         (let-values ([(xs m)
                       (match αₖ
                         [(-ℬ xs _ _)
                          (define bounds (formals->names xs))
                          (define m
                            (match xs
                              [(? list? xs)
                               (for/hash : Subst ([x xs] [sₓ sₓs] #:when sₓ)
                                 (values (-x x) sₓ))]
                              [(-varargs xs x)
                               (define-values (args-init args-rest) (split-at sₓs (length xs)))
                               (define m-init
                                 (for/hash : Subst ([x xs] [arg args-init] #:when arg)
                                   (values (-x x) arg)))
                               (define s-rst (-?list args-rest))
                               (if s-rst (hash-set m-init (-x x) s-rst) m-init)]))
                          (values bounds m)]
                         [(-ℳ x _ _ _ _)
                          (define sₓ (car sₓs))
                          (values {seteq x} (if sₓ (hash-set m∅ (-x x) sₓ) m∅))]
                         [(-ℱ x _ _ _ _)
                          (define sₓ (car sₓs))
                          (values {seteq x} (if sₓ (hash-set m∅ (-x x) sₓ) m∅))])])
           (define φ-ans
             (match Vs
               [(list V)
                (match V
                  [(? -v? v)
                   (-?@ 'equal? (apply -?@ sₕ sₓs) v)]
                  [(or (? -Clo?) (? -Ar?) (? -o?))
                   (-?@ 'procedure? (apply -?@ sₕ sₓs))]
                  [_ #f])]
               [_ #f]))
           (define φs-path
             (for/fold ([φs-path : (℘ -e) ∅]) ([φ (-Γ-facts Γₑₑ)])
               (cond
                 [(⊆ (fv φ) xs) (set-add φs-path (e/map m φ))]
                 [else φs-path])))
           (apply Γ+ Γₑᵣ* φ-ans (set->list φs-path))))
       (cond
         [(plausible-pc? M Γₑᵣ**)
          (define sₐ*
            (and sₐ
                 (match fargs ; HACK
                   [(-@ 'fc (list x) _)
                    (match Vs
                      [(list (-b #f)) -ff]
                      [(list (-b #t) _) (-?@ 'values -tt x)])]
                   [_ fargs])))
          (⟦k⟧ (-W Vs sₐ*) $∅ Γₑᵣ* 𝒞ₑᵣ Σ)]
         [else ∅])]
      [(? -blm? blm) ; TODO: faster if had next `αₖ` here 
       (match-define (-blm l+ lo _ _) blm)
       (case l+
         [(havoc † Λ) ∅]
         [else
          (define γ (-γ αₖ (cons l+ lo) sₕ sₓs))
          (define Γₑᵣ* (-Γ-plus-γ Γₑᵣ γ))
          (cond
            [(plausible-pc? M Γₑᵣ*)
             (⟦k⟧ blm $∅ Γₑᵣ* 𝒞ₑᵣ Σ)]
            [else ∅])])])))
