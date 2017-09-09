#lang typed/racket/base

(provide val@)

(require typed/racket/unit
         racket/match
         racket/set
         racket/splicing
         set-extras
         "../utils/main.rkt"
         "../ast/signatures.rkt"
         "signatures.rkt")

(define-unit val@
  (import pc^ pretty-print^ sto^)
  (export val^)

  (define +● : (-h * → -●)
    (let ([m : (HashTable (Listof -h) -●) (make-hash)])
      (λ hs
        (hash-ref! m hs (λ () (-● (list->set hs)))))))

  (define +W¹ : ([-prim] [-?t] . ->* . -W¹)
    (let ([m : (HashTable -W¹ -W¹) (make-hash)])
      (λ ([b : -prim] [t : -?t b])
        (define W (-W¹ b t))
        (hash-ref! m W (λ () W)))))

  (define +W : ([(Listof -prim)] [-?t] . ->* . -W)
    (let ([m : (HashTable -W -W) (make-hash)])
      (λ ([bs : (Listof -prim)] [t : -?t (apply ?t@ 'values bs)])
        (define W (-W bs t))
        (hash-ref! m W (λ () W)))))

  (define (W¹->W [W : -W¹])
    (match-define (-W¹ V s) W)
    (-W (list V) s))

  (define (W->W¹s [W : -W]) : (Listof -W¹)
    (match-define (-W Vs t) W)
    (for/list ([Vᵢ (in-list Vs)]
               [tᵢ (in-list (split-values t (length Vs)))])
      (-W¹ Vᵢ tᵢ)))

  (: C-flat? : -V → Boolean)
  ;; Check whether contract is flat, assuming it's already a contract
  (define (C-flat? V)
    (match V
      [(-And/C flat? _ _) flat?]
      [(-Or/C flat? _ _) flat?]
      [(? -Not/C?) #t]
      [(? -One-Of/C?) #t]
      [(-St/C flat? _ _) flat?]
      [(or (? -Vectorof?) (? -Vector/C?)) #f]
      [(-Hash/C _ _) #f] ; TODO
      [(-Set/C _) #f] ; TODO
      [(? -=>_?) #f]
      [(or (? -Clo?) (? -Ar?) (? -prim?)) #t]
      [(? -x/C?) #t]
      [(? -∀/C?) #f]
      [(? -Seal/C?) #f]
      [V (error 'C-flat? "Unepxected: ~a" (show-V V))]))


  (splicing-local
      ((: with-swapper : (-l -ctx → -ctx) → -l -V → -V)
       (define ((with-swapper swap) l V)
         (match V
           [(-Ar C α ctx)
            (-Ar C α (swap l ctx))]
           [(-St* grd α ctx)
            (-St* grd α (swap l ctx))]
           [(-Vector/guard grd α ctx)
            (-Vector/guard grd α (swap l ctx))]
           [(-Hash/guard C α ctx)
            (-Hash/guard C α (swap l ctx))]
           [(-Set/guard C α ctx)
            (-Set/guard C α (swap l ctx))]
           [_ V])))
    (define with-negative-party
      (with-swapper
        (match-lambda**
          [(l (-ctx l+ _ lo ℓ))
           (-ctx l+ l lo ℓ)])))
    (define with-positive-party
      (with-swapper
        (match-lambda**
          [(l (-ctx _ l- lo ℓ))
           (-ctx l l- lo ℓ)]))))

  (: behavioral? : -σ -V → Boolean)
  ;; Check if value maybe behavioral.
  ;; `#t` is a conservative answer "maybe yes"
  ;; `#f` is a strong answer "definitely no"
  (define (behavioral? σ V)
    (define-set seen : ⟪α⟫ #:eq? #t #:as-mutable-hash? #t)

    (: check-⟪α⟫! : ⟪α⟫ → Boolean)
    (define (check-⟪α⟫! ⟪α⟫)
      (cond [(seen-has? ⟪α⟫) #f]
            [else
             (seen-add! ⟪α⟫)
             (for/or ([V (σ@ σ ⟪α⟫)])
               (check! V))]))

    (: check! : -V → Boolean)
    (define (check! V)
      (match V
        [(-St _ αs) (ormap check-⟪α⟫! αs)]
        [(-St* _ α _) (check-⟪α⟫! α)]
        [(-Vector αs) (ormap check-⟪α⟫! αs)]
        [(-Vector^ α _) (check-⟪α⟫! α)]
        [(-Ar grd α _) #t]
        [(-=> doms rngs _)
         (match doms
           [(? list? doms)
            (or (for/or : Boolean ([dom (in-list doms)])
                  (check-⟪α⟫! (-⟪α⟫ℓ-addr dom)))
                (and (pair? rngs)
                     (for/or : Boolean ([rng (in-list rngs)])
                       (check-⟪α⟫! (-⟪α⟫ℓ-addr rng)))))]
           [(-var doms dom)
            (or (check-⟪α⟫! (-⟪α⟫ℓ-addr dom))
                (for/or : Boolean ([dom (in-list doms)])
                  (check-⟪α⟫! (-⟪α⟫ℓ-addr dom)))
                (and (pair? rngs)
                     (for/or : Boolean ([rng (in-list rngs)])
                       (check-⟪α⟫! (-⟪α⟫ℓ-addr rng)))))])]
        [(? -=>i?) #t]
        [(-Case-> cases _)
         (for*/or : Boolean ([kase : (Pairof (Listof ⟪α⟫) ⟪α⟫) cases])
           (match-define (cons doms rng) kase)
           (or (check-⟪α⟫! rng)
               (ormap check-⟪α⟫! doms)))]
        [(or (? -Clo?) (? -Case-Clo?)) #t]
        [_ #f]))

    (check! V))

  (define guard-arity : (-=>_ → Arity)
    (match-lambda
      [(-=> αs _ _) (shape αs)]
      [(and grd (-=>i αs (list mk-D mk-d _) _))
       (match mk-D
         [(-Clo xs _ _ _) (shape xs)]
         [_
          ;; FIXME: may be wrong for var-args. Need to have saved more
          (length αs)])]
      [(? -∀/C?)
       ;; TODO From observing behavior in Racket. But this maybe unsound for proof system
       (arity-at-least 0)]))

  (: blm-arity : ℓ -l Arity (Listof -V) → -blm)
  (define blm-arity
    (let ([arity->msg : (Arity → Symbol)
                      (match-lambda
                        [(? integer? n)
                         (format-symbol (case n
                                          [(0 1) "~a value"]
                                          [else "~a values"])
                                        n)]
                        [(arity-at-least n)
                         (format-symbol "~a+ values" n)])])
      (λ (ℓ lo arity Vs)
        (-blm (ℓ-src ℓ) lo (list (arity->msg arity)) Vs ℓ))))

  (: strip-C : -V → -edge.tgt)
  (define strip-C
    (match-lambda
      [(-Clo xs ⟦e⟧ _ _) (list 'flat ⟦e⟧)] ; distinct from just ⟦e⟧
      [(-And/C _ (-⟪α⟫ℓ _ ℓ₁) (-⟪α⟫ℓ _ ℓ₂)) (list 'and/c ℓ₁ ℓ₂)]
      [(-Or/C  _ (-⟪α⟫ℓ _ ℓ₁) (-⟪α⟫ℓ _ ℓ₂)) (list  'or/c ℓ₁ ℓ₂)]
      [(-Not/C (-⟪α⟫ℓ _ ℓ)) (list 'not/c ℓ)]
      [(-One-Of/C bs) bs]
      [(-St/C _ (-𝒾 𝒾 _) ⟪α⟫ℓs) (cons 𝒾 (map -⟪α⟫ℓ-loc ⟪α⟫ℓs))]
      [(-Vectorof (-⟪α⟫ℓ _ ℓ)) (list 'vectorof ℓ)]
      [(-Vector/C ⟪α⟫ℓs) (cons 'vector/c (map -⟪α⟫ℓ-loc ⟪α⟫ℓs))]
      [(-Hash/C (-⟪α⟫ℓ _ ℓₖ) (-⟪α⟫ℓ _ ℓᵥ)) (list 'hash/c ℓₖ ℓᵥ)]
      [(-Set/C (-⟪α⟫ℓ _ ℓ)) (list 'set/c ℓ)]
      [(-=> _ _ ℓ) (list '-> ℓ)]
      [(-=>i _ _ ℓ) (list '->i ℓ)]
      [(-Case-> _ ℓ) (list 'case-> ℓ)]
      [(-x/C α)
       (match-define (or (-α.x/c x _) (-α.imm-listof x _)) (⟪α⟫->-α α))
       (list 'recursive-contract/c x)]
      [(? -o? o) o]
      [(-Ar _ (app ⟪α⟫->-α (-α.fn _ ctx _ _)) _) (list 'flat (-ctx-loc ctx))]
      [(-∀/C xs ⟦c⟧ ρ) (list '∀/c ⟦c⟧)]
      [(-Seal/C x _ _) (list 'seal/c x)]
      [(-b b) (list 'flat (-b b))]
      [V (error 'strip-C "~a not expected" V)]))

  (: predicates-of-V : -V → (℘ -h))
  (define predicates-of-V
    (match-lambda
      [(-b (? number?)) {set 'number?}]
      [(-b (? null?)) {set 'null?}]
      [(-Clo _ ⟦e⟧ _ _) {set (-clo ⟦e⟧)}]
      [(or (-St 𝒾 _) (-St* (-St/C _ 𝒾 _) _ _)) #:when 𝒾 {set (-st-p 𝒾)}]
      [(or (? -Ar?) (? -o?)) {set 'procedure?}]
      [_ ∅]))

  )
