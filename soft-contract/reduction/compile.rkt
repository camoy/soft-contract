#lang typed/racket/base

(provide compile@)

(require (for-syntax racket/base
                     racket/syntax
                     syntax/parse)
         (only-in racket/function const)
         racket/set
         racket/list
         racket/match
         typed/racket/unit
         syntax/parse/define
         set-extras
         "../utils/main.rkt"
         "../ast/signatures.rkt"
         "../runtime/signatures.rkt"
         "../proof-relation/signatures.rkt"
         "../signatures.rkt"
         "signatures.rkt"
         )

(define-unit compile@
  (import meta-functions^ ast-pretty-print^
          kont^ proof-system^
          env^ sto^ path^ val^ pretty-print^ for-gc^)
  (export compile^)

  (: ↓ₚ : (Listof -module) -e → -⟦e⟧)
  ;; Compile program
  (define (↓ₚ ms e)
    (with-cases-on ms (ρ H φ Σ ⟦k⟧)
      ['() #:reduce (↓ₑ '† e)]
      [(cons m ms)
       (⟦m⟧ ρ H φ Σ (bgn∷ `(,@⟦m⟧s ,⟦e⟧) ρ ⟦k⟧))
       #:where
       [⟦m⟧ (↓ₘ m)]
       [⟦m⟧s (map ↓ₘ ms)]
       [⟦e⟧ (↓ₑ '† e)]]))

  (: ↓ₘ : -module → -⟦e⟧)
  ;; Compile module
  (define (↓ₘ m)
    (match-define (-module l ds) m)

    (: ↓pc : -provide-spec → -⟦e⟧)
    (define (↓pc spec)
      (with-cases-on spec (ρ H φ Σ ⟦k⟧)
        ;; Wrap contract
        [(-p/c-item x c ℓ)
         (⟦c⟧ ρ H φ Σ (dec∷ ℓ 𝒾 ⟦k⟧))
         #:where
         [⟦c⟧ (↓ₑ l c)]
         [𝒾 (-𝒾 x l)]]
        ;; Export same as internal
        [(? symbol? x)
         (begin (assert (defined-at? Σ (-φ-cache φ) α))
                (⟦k⟧ A H (alloc Σ φ α* (σ@ Σ (-φ-cache φ) α)) Σ))
         #:where
         [α  (-α->⟪α⟫ (-𝒾 x l))]
         [α* (-α->⟪α⟫ (-α.wrp (-𝒾 x l)))]
         [A  (list {set -void})]]))
    
    (: ↓d : -module-level-form → -⟦e⟧)
    (define (↓d d)
      (with-cases-on d (ρ H φ Σ ⟦k⟧)
        [(-define-values xs e)
         (⟦e⟧ ρ H φ Σ (def∷ l αs ⟦k⟧))
         #:where
         [αs (for/list : (Listof ⟪α⟫) ([x xs]) (-α->⟪α⟫ (-𝒾 x l)))]
         [⟦e⟧ (↓ₑ l e)]]
        [(-provide '()) #:reduce (mk-V -void)]
        [(-provide (cons spec specs))
         (⟦spec⟧ ρ H φ Σ (bgn∷ ⟦spec⟧s ρ ⟦k⟧))
         #:where
         [⟦spec⟧ (↓pc spec)]
         [⟦spec⟧s (map ↓pc specs)]]
        [(? -e? e) #:reduce (↓ₑ l e)]
        [_ #:reduce (begin0 (mk-V -void)
                      (log-warning "↓d: ignore ~a~n" (show-module-level-form d)))]))

    (with-cases-on ds (ρ H φ Σ ⟦k⟧)
      ['() #:reduce (mk-V -void)]
      [(cons d ds)
       (⟦d⟧ ρ H φ Σ (bgn∷ ⟦d⟧s ρ ⟦k⟧))
       #:where
       [⟦d⟧ (↓d d)]
       [⟦d⟧s (map ↓d ds)]]))

  (: ↓ₑ : -l -e → -⟦e⟧)
  ;; Compile expression to computation
  (define (↓ₑ l e)
    
    (let ↓ : -⟦e⟧ ([e : -e e])
         (: ↓-bnd : (Pairof (Listof Symbol) -e) → (Pairof (Listof Symbol) -⟦e⟧))
         (define (↓-bnd bnd)
           (match-define (cons x eₓ) bnd)
           (cons x (↓ eₓ)))
         (: ↓* : (Listof -e) → (Listof -⟦e⟧))
         (define (↓* es) (map ↓ es))
         (define-match-expander :↓  (syntax-rules () [(_ e ) (app ↓  e )]))
         (define-match-expander :↓* (syntax-rules () [(_ es) (app ↓* es)]))
         
      (remember-e!
       e
       (with-cases-on e (ρ H φ Σ ⟦k⟧)
         [(and lam (-λ xs (:↓ ⟦e*⟧)))
          (⟦k⟧ (list {set (-Clo xs ⟦e*⟧ (m↓ ρ fvs))}) H φ Σ)
          #:where [fvs (fv lam)]]
         [(? -prim? p) #:reduce (mk-V p)]
         [(-•) #:reduce (mk-V (fresh-sym!))]
         [(-x (? symbol? x) ℓₓ) #:reduce (↓ₓ l x ℓₓ)]
         [(-x (and 𝒾 (-𝒾 x l₀)) _)
          (let* ([φ* (if (hash-has-key? (-Σ-σ Σ) ⟪α⟫ₒₚ)
                         (alloc Σ φ ⟪α⟫ₒₚ {set (-● ∅)})
                         φ)]
                 [V^ (map/set modify-V (σ@ Σ (-φ-cache φ*) α))])
            (⟦k⟧ (list V^) H φ* Σ))
          #:where
          [α (-α->⟪α⟫ (if (equal? l₀ l) 𝒾 (-α.wrp 𝒾)))]
          [modify-V
           (ann (cond
                  [(equal? l₀ l) values]
                  [(symbol? l) (λ (V) (with-negative-party l V))]
                  [else
                   (λ (V)
                     (with-positive-party 'dummy+
                       (with-negative-party l
                         (match V
                           [(-Ar C _ l³)
                            (-Ar C (-α->⟪α⟫ (-α.imm (-Fn● (guard-arity C) '†))) l³)]
                           [(-St* C _ l³)
                            (-St* C ⟪α⟫ₒₚ l³)]
                           [(-Vector/guard C _ l³)
                            (-Vector/guard C ⟪α⟫ₒₚ l³)]
                           [_ V]))))])
                (-V → -V))]]
         [(-@ (:↓ ⟦f⟧) (:↓* ⟦x⟧s) ℓ)
          (⟦f⟧ ρ H φ Σ (ap∷ '() ⟦x⟧s ρ ℓ ⟦k⟧))]
         [(-if (:↓ ⟦e₀⟧) (:↓ ⟦e₁⟧) (:↓ ⟦e₂⟧))
          (⟦e₀⟧ ρ H φ Σ (if∷ l ⟦e₁⟧ ⟦e₂⟧ ρ ⟦k⟧))]
         [(-wcm k v b) #:reduce (error '↓ₑ "TODO: wcm")]
         [(-begin '()) #:reduce (mk-V -void)]
         [(-begin (cons (:↓ ⟦e⟧) (:↓* ⟦e⟧s)))
          (⟦e⟧ ρ H φ Σ (bgn∷ ⟦e⟧s ρ ⟦k⟧))]
         [(-begin0 (:↓ ⟦e₀⟧) (:↓* ⟦e⟧s))
          (⟦e₀⟧ ρ H φ Σ (bgn0.v∷ ⟦e⟧s ρ ⟦k⟧))]
         [(-quote (? Base? q)) #:reduce (mk-V (-b q))]
         [(-quote q) (error '↓ₑ "TODO: (quote ~a)" q)]
         [(-let-values '() e* ℓ) #:reduce (↓ e*)]
         [(-let-values bnds (:↓ ⟦e*⟧) ℓ)
          (⟦e⟧ₓ ρ H φ Σ (let∷ ℓ x ⟦bnd⟧s '() ⟦e*⟧ ρ ⟦k⟧))
          #:where [(cons (cons x ⟦e⟧ₓ) ⟦bnd⟧s) (map ↓-bnd bnds)]]
         [(-letrec-values '() e* ℓ) #:reduce (↓ e*)]
         [(-letrec-values bnds (:↓ ⟦e*⟧) ℓ)
          (let-values ([(ρ* φ*) (init-undefined Σ H ρ φ)])
            (⟦e⟧ₓ ρ* H φ* Σ (letrec∷ ℓ x ⟦bnd⟧s* ⟦e*⟧ ρ* ⟦k⟧)))
          #:where
          [(cons (cons x ⟦e⟧ₓ) ⟦bnd⟧s*) (map ↓-bnd bnds)]
          [init-undefined
           (λ ([Σ : -Σ] [H : -H] [ρ : -ρ] [φ : -φ])
             (for*/fold ([ρ : -ρ ρ] [φ : -φ φ])
                        ([bnd (in-list bnds)] [x (in-list (car bnd))])
               (define α (-α->⟪α⟫ (-α.x x H)))
               (values (ρ+ ρ x α) (alloc Σ φ α {set -undefined}))))]]
         [(-set! x (:↓ ⟦e*⟧))
          (⟦e*⟧ ρ H φ Σ (set!∷ (get-addr ρ) ⟦k⟧))
          #:where
          [get-addr
           (if (symbol? x)
               (λ ([ρ : -ρ]) (ρ@ ρ x))
               (const (-α->⟪α⟫ x)))]]
         [(-error msg ℓ) #:reduce (mk-A (blm/simp (ℓ-src ℓ) 'Λ '(not-reached) (list {set (-b msg)}) ℓ))]
         [(-μ/c x (:↓ ⟦c⟧))
          (⟦c⟧ (ρ+ ρ x (-α->⟪α⟫ (-α.x/c x H))) H φ Σ (μ/c∷ x ⟦k⟧))]
         [(--> cs d ℓ) #:reduce (mk--> ℓ (-var-map ↓ cs) (↓ d))]
         [(-->i cs d) #:reduce (mk-->i (map (↓dom l) cs) ((↓dom l) d))]
         [(-∀/c xs (and e* (:↓ ⟦e*⟧)))
          (⟦k⟧ (list {set (-∀/C xs ⟦e*⟧ (m↓ ρ fvs))}) H φ Σ)
          #:where
          [fvs (fv e*)]]
         [(-x/c x)
          (⟦k⟧ (list {set (-x/C (ρ@ ρ x))}) H φ Σ)]
         [(-struct/c 𝒾 cs ℓ)
          #:reduce
          (with-cases-on cs (ρ H φ Σ ⟦k⟧)
            ['()
             (⟦k⟧ (if (struct-defined? Σ φ) C blm) H φ Σ)
             #:where [C (list {set (-St/C #t 𝒾 '())})]]
            [(cons (:↓ ⟦c⟧) (:↓* ⟦c⟧s))
             (if (struct-defined? Σ φ)
                 (⟦c⟧ ρ H φ Σ (struct/c∷ ℓ 𝒾 '() ⟦c⟧s ρ ⟦k⟧))
                 (⟦k⟧ blm H φ Σ))])
          #:where
          [α (-α->⟪α⟫ 𝒾)]
          [blm (blm/simp l 'Λ '(struct-defined?) (list {set (-𝒾-name 𝒾)}) ℓ)]
          [builtin-struct-tag? (match? 𝒾 (== -𝒾-cons) (== -𝒾-box))]
          [struct-defined?
           (if builtin-struct-tag?
               (λ _ #t)
               (λ ([Σ : -Σ] [φ : -φ]) (defined-at? Σ (-φ-cache φ) α)))]]
         [_ (error '↓ₑ "unhandled: ~a" (show-e e))]
         ))))

  (: ↓dom : -l → -dom → -⟦dom⟧)
  (define ((↓dom l) dom)
    (match-define (-dom xs ?dep e ℓ) dom)
    (-⟦dom⟧ xs ?dep (↓ₑ l e) ℓ))

  (define/memo (mk-->i [⟦dom⟧s : (Listof -⟦dom⟧)] [⟦rng⟧ : -⟦dom⟧]) : -⟦e⟧
    (remember-e!
     (string->symbol (format "~a" `(->i ,(map show-⟦dom⟧ ⟦dom⟧s) ,(show-⟦dom⟧ ⟦rng⟧))))
     (λ (ρ H φ Σ ⟦k⟧)
      (define-values (Doms doms) (split-⟦dom⟧s ρ (append ⟦dom⟧s (list ⟦rng⟧))))
      (match doms
        ['()
         (⟦k⟧ (list {set (mk-=>i Σ H φ Doms)}) H φ Σ)]
        [(cons (-⟦dom⟧ x #f ⟦c⟧ ℓ) ⟦dom⟧s)
         (⟦c⟧ ρ H φ Σ (-->i∷ ρ Doms (cons x ℓ) ⟦dom⟧s ⟦k⟧))])))
    )

  (define/memo (mk--> [ℓ : ℓ] [⟦dom⟧s : (-maybe-var -⟦e⟧)] [⟦rng⟧ : -⟦e⟧]) : -⟦e⟧
    (remember-e!
     (string->symbol (format "~a" `(-> … ,(show-⟦e⟧ ⟦rng⟧))))
     (with-cases-on ⟦dom⟧s (ρ H φ Σ ⟦k⟧)
      ['()            (⟦rng⟧ ρ H φ Σ (-->.rng∷ '() #f ℓ ⟦k⟧))]
      [(cons ⟦c⟧ ⟦c⟧s) (⟦c⟧   ρ H φ Σ (-->.dom∷ '() ⟦c⟧s #f ⟦rng⟧ ρ ℓ ⟦k⟧))]
      [(-var ⟦c⟧s ⟦cᵣ⟧)
       #:reduce
       (with-cases-on ⟦c⟧s (ρ H φ Σ ⟦k⟧)
         ['()            (⟦cᵣ⟧ ρ H φ Σ (-->.rst∷ '() ⟦rng⟧ ρ ℓ ⟦k⟧))]
         [(cons ⟦c⟧ ⟦c⟧s) (⟦c⟧  ρ H φ Σ (-->.dom∷ '() ⟦c⟧s ⟦cᵣ⟧ ⟦rng⟧ ρ ℓ ⟦k⟧))])])))

  (define (mk-V [V : -V])
    (define ans (mk-A (list {set V})))
    (if (-e? V) (remember-e! V ans) ans))

  (define/memo (mk-let* [ℓ : ℓ]
                        [⟦bind⟧s : (Listof (Pairof Symbol -⟦e⟧))]
                        [⟦body⟧ : -⟦e⟧]) : -⟦e⟧
    (foldr
     (λ ([⟦bind⟧ : (Pairof Symbol -⟦e⟧)] [⟦body⟧ : -⟦e⟧]) : -⟦e⟧
       (match-define (cons (app list x) ⟦e⟧ₓ) ⟦bind⟧)
       (λ (ρ H φ Σ ⟦k⟧)
         (⟦e⟧ₓ ρ H φ Σ (let∷ ℓ x '() '() ⟦body⟧ ρ ⟦k⟧))))
     ⟦body⟧
     ⟦bind⟧s))

  (define/memo (↓ₓ [l : -l] [x : Symbol] [ℓₓ : ℓ]) : -⟦e⟧
    (define -blm.undefined
      (blm/simp l 'Λ (list 'defined?) (list {set (format-symbol "~a_(~a)" 'undefined x)}) ℓₓ))
    (remember-e!
     (-x x ℓₓ)
     (λ (ρ H φ Σ ⟦k⟧)
       (for/union : (℘ -ς) ([V-φ (in-list (σ@/cache Σ φ (ρ@ ρ x)))])
          (match-define (cons V^ φ*) V-φ)
          (define (on-ok) (⟦k⟧ {list (set-remove V^ -undefined)} H φ* Σ))
          (define (on-er) (⟦k⟧ -blm.undefined H φ* Σ))
          (if (∋ V^ -undefined)
              (∪ (on-ok) (on-er))
              (on-ok))))))

  (define/memo (mk-mon [ctx : -ctx] [⟦c⟧ : -⟦e⟧] [⟦e⟧ : -⟦e⟧]) : -⟦e⟧
    (λ (ρ H φ Σ ⟦k⟧)
      (⟦c⟧ ρ H φ Σ (mon.v∷ ctx (cons ⟦e⟧ ρ) ⟦k⟧))))

  (define/memo (mk-app [ℓ : ℓ] [⟦f⟧ : -⟦e⟧] [⟦x⟧s : (Listof -⟦e⟧)]) : -⟦e⟧
    (remember-e!
     (string->symbol (format "~a" (cons (show-⟦e⟧ ⟦f⟧) (map show-⟦e⟧ ⟦x⟧s))))
     (λ (ρ H φ Σ ⟦k⟧)
      (⟦f⟧ ρ H φ Σ (ap∷ '() ⟦x⟧s ρ ℓ ⟦k⟧)))))

  (define/memo (mk-A [A : -A]) : -⟦e⟧
    (λ (_ H φ Σ ⟦k⟧)
      (⟦k⟧ A H φ Σ)))

  (define/memo (mk-fc [l : -l] [ℓ : ℓ] [⟦c⟧ : -⟦e⟧] [⟦v⟧ : -⟦e⟧]) : -⟦e⟧
    (λ (ρ H φ Σ ⟦k⟧)
      (⟦c⟧ ρ H φ Σ (fc.v∷ l ℓ ⟦v⟧ ρ ⟦k⟧))))

  (define/memo (mk-wrapped-hash [C : -Hash/C] [ctx : -ctx] [α : ⟪α⟫] [V : -V^]) : -⟦e⟧
    (λ (ρ H φ Σ ⟦k⟧)
      (⟦k⟧ (list {set (-Hash/guard C α ctx)}) H (alloc Σ φ α V) Σ)))

  (define/memo (mk-wrapped-set [C : -Set/C] [ctx : -ctx] [α : ⟪α⟫] [V : -V^]) : -⟦e⟧
    (λ (ρ H φ Σ ⟦k⟧)
      (⟦k⟧ (list {set (-Set/guard C α ctx)}) H (alloc Σ φ α V) Σ)))

  (: split-⟦dom⟧s : -ρ (Listof -⟦dom⟧) → (Values (Listof -Dom) (Listof -⟦dom⟧)))
  (define (split-⟦dom⟧s ρ ⟦dom⟧s)
    (let go ([Doms↓ : (Listof -Dom) '()] [⟦dom⟧s : (Listof -⟦dom⟧) ⟦dom⟧s])
      (match ⟦dom⟧s
        ['() (values Doms↓ '())]
        [(cons ⟦dom⟧ ⟦dom⟧s*)
         (match-define (-⟦dom⟧ x ?dep ⟦e⟧ ℓ) ⟦dom⟧)
         (match ?dep
           [(? values) (go (cons (-Dom x (-Clo ?dep ⟦e⟧ ρ) ℓ) Doms↓) ⟦dom⟧s*)]
           [#f (values Doms↓ ⟦dom⟧s)])])))

  (define-syntax-parser with-cases-on
    [(_ e:expr (ρ:id H:id φ:id Σ:id ⟦k⟧:id) clauses ...)
     (define parse-clause
       (syntax-parser
         [[e-pat #:reduce expr
                 (~optional (~seq #:where [x d] ...)
                            #:defaults ([(x 1) null]
                                        [(d 1) null]))]
          #`[e-pat
             (match-define x d) ...
             expr]]
         [[e-pat rhs
                 (~optional (~seq #:where [x d] ...)
                            #:defaults ([(x 1) null]
                                        [(d 1) null]))]
          #'[e-pat
             (match-define x d) ...
             (λ (ρ H φ Σ ⟦k⟧) rhs)]]))
     #`(match e #,@(map parse-clause (syntax->list #'(clauses ...))))])
  )
