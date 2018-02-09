#lang typed/racket/base

(provide meta-functions@)

(require racket/match
         racket/set
         (only-in racket/function curry)
         racket/list
         racket/bool
         typed/racket/unit
         set-extras
         "../utils/main.rkt"
         "signatures.rkt")

(define-unit meta-functions@
  (import static-info^)
  (export meta-functions^)

  (: fv : (U -e (Listof -e)) → (℘ Symbol))
  ;; Compute free variables for expression. Return set of variable names.
  (define (fv e)
    (match e
      [(-x x _) (if (symbol? x) {seteq x} ∅eq)]
      [(-x/c x) {seteq x}]
      [(-λ xs e)
       (define bound
         (match xs
           [(-var zs z) (set-add (list->seteq zs) z)]
           [(? list? xs) (list->seteq xs)]))
       (set-remove (fv e) bound)]
      [(-@ f xs _)
       (for/fold ([FVs (fv f)]) ([x xs]) (∪ FVs (fv x)))]
      [(-begin es) (fv es)]
      [(-begin0 e₀ es) (∪ (fv e₀) (fv es))]
      [(-let-values bnds e _)
       (define-values (bound FV_rhs)
         (for/fold ([bound : (℘ Symbol) ∅eq] [FV_rhs : (℘ Symbol) ∅eq]) ([bnd bnds])
           (match-define (cons xs rhs) bnd)
           (values (set-add* bound xs) (∪ FV_rhs (fv rhs)))))
       (∪ FV_rhs (set-remove (fv e) bound))]
      [(-letrec-values bnds e _)
       (define bound
         (for/fold ([bound : (℘ Symbol) ∅eq]) ([bnd bnds])
           (set-add* bound (car bnd))))
       
       (for/fold ([xs : (℘ Symbol) (set-remove (fv e) bound)]) ([bnd bnds])
         (set-remove (fv (cdr bnd)) bound))]
      [(-set! x e)
       (match x
         [(? symbol? x) (set-add (fv e) x)]
         [_ (fv e)])]
      #;[(.apply f xs _) (set-union (fv f d) (fv xs d))]
      [(-if e e₁ e₂) (∪ (fv e) (fv e₁) (fv e₂))]
      [(-μ/c _ e) (fv e)]
      [(--> cs d _)
       (match cs
         [(-var cs c) (∪ (fv c) (fv d) (fv cs))]
         [(? list? cs) (∪ (fv d) (fv cs))])]
      [(-->i cs d)
       (define dom-fv : (-dom → (℘ Symbol))
         (match-lambda
           [(-dom _ ?xs d _) (fv (if ?xs (-λ ?xs d) d))]))
       (apply ∪ (dom-fv d) (map dom-fv cs))]
      [(-struct/c _ cs _)
       (for/fold ([xs : (℘ Symbol) ∅eq]) ([c cs])
         (∪ xs (fv c)))]
      [(? list? l)
       (for/fold ([xs : (℘ Symbol) ∅eq]) ([e l])
         (∪ xs (fv e)))]
      [_ (log-debug "FV⟦~a⟧ = ∅~n" e) ∅eq]))

  (: closed? : -e → Boolean)
  ;; Check whether expression is closed
  (define (closed? e) (set-empty? (fv e)))

  (: free-x/c : -e → (℘ Symbol))
  ;; Return all free references to recursive contracts inside term
  (define (free-x/c e)

    (: go* : (Listof -e) → (℘ Symbol))
    (define (go* xs) (for/unioneq : (℘ Symbol) ([x xs]) (go x)))

    (: go/dom : -dom → (℘ Symbol))
    (define go/dom
      (match-lambda
        [(-dom _ ?xs d _) (if ?xs (go (-λ ?xs d)) (go d))]))

    (: go : -e → (℘ Symbol))
    (define (go e)
      (match e
        [(-λ xs e) (go e)]
        [(-@ f xs ctx) (∪ (go f) (go* xs))]
        [(-if i t e) (∪ (go i) (go t) (go e))]
        [(-wcm k v b) (∪ (go k) (go v) (go b))]
        [(-begin0 e es) (∪ (go e) (go* es))]
        [(-let-values bnds e _)
         (∪ (for/unioneq : (℘ Symbol) ([bnd bnds]) (go (cdr bnd))) (go e))]
        [(-letrec-values bnds e _)
         (∪ (for/unioneq : (℘ Symbol) ([bnd bnds]) (go (cdr bnd))) (go e))]
        [(-μ/c _ c) (go c)]
        [(--> cs d _)
         (match cs
           [(-var cs c) (∪ (go* cs) (go c) (go d))]
           [(? list? cs) (∪ (go* cs) (go d))])]
        [(-->i cs d) (apply ∪ (go/dom d) (map go/dom cs))]
        [(-struct/c t cs _) (go* cs)]
        [(-x/c.tmp x) (seteq x)]
        [_ ∅eq]))
    
    (go e))

  #;(: find-calls : -e (U -𝒾 -•) → (℘ (Listof -e)))
  ;; Search for all invocations of `f-id` in `e`
  #;(define (find-calls e f-id)
      (define-set calls : (Listof -e))
      (let go! : Void ([e e])
           (match e
             [(-@ f xs _)
              (go! f)
              (for-each go! xs)
              (when (equal? f f-id)
                (calls-add! xs))]
             [_ (void)]))
      calls)


  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;;;;; Substitution
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


  (define (e/map [m : Subst] [e : -e])

    (: go-list : Subst (Listof -e) → (Listof -e))
    (define (go-list m es)
      (for/list : (Listof -e) ([e es]) (go m e)))

    (: go : Subst -e → -e)
    (define (go m e)
      (with-debugging/off
        ((ans)
         (define go/dom : (-dom → -dom)
           (match-lambda
             [(-dom x ?xs d ℓ)
              (define d* (if ?xs (go (remove-keys m (list->seteq ?xs)) d) (go m d)))
              (-dom x ?xs d* ℓ)]))
         (cond
           [(hash-empty? m) e]
           [else
            (match e
              [(or (-x x _) (-x/c.tmp x))
               #:when x
               (hash-ref m x (λ () e))]
              [(-λ xs e*)
               (-λ xs (go (remove-keys m (formals->names xs)) e*))]
              [(-@ f xs ℓ)
               (-@ (go m f) (go-list m xs) ℓ)]
              [(-if e₀ e₁ e₂)
               (-if (go m e₀) (go m e₁) (go m e₂))]
              [(-wcm k v b)
               (-wcm (go m k) (go m v) (go m b))]
              [(-begin es)
               (-begin (go-list m es))]
              [(-begin0 e₀ es)
               (-begin0 (go m e₀) (go-list m es))]
              [(-let-values bnds body ℓ)
               (define-values (bnds*-rev locals)
                 (for/fold ([bnds*-rev : (Listof (Pairof (Listof Symbol) -e)) '()]
                            [locals : (℘ Symbol) ∅eq])
                           ([bnd bnds])
                   (match-define (cons xs eₓ) bnd)
                   (values (cons (cons xs (go m eₓ)) bnds*-rev)
                           (set-add* locals xs))))
               (define body* (go (remove-keys m locals) body))
               (-let-values (reverse bnds*-rev) body* ℓ)]
              [(-letrec-values bnds body ℓ)
               (define locals
                 (for/fold ([locals : (℘ Symbol) ∅eq])
                           ([bnd bnds])
                   (match-define (cons xs _) bnd)
                   (set-add* locals xs)))
               (define m* (remove-keys m locals))
               (define bnds* : (Listof (Pairof (Listof Symbol) -e))
                 (for/list ([bnd bnds])
                   (match-define (cons xs eₓ) bnd)
                   (cons xs (go m* eₓ))))
               (define body* (go m* body))
               (-letrec-values bnds* body* ℓ)]
              [(-set! x e*)
               (assert (not (hash-has-key? m x)))
               (-set! x (go m e*))]
              [(-μ/c z c)
               (-μ/c z (go (remove-keys m {seteq z}) c))]
              [(--> cs d ℓ)
               (match cs
                 [(-var cs c) (--> (-var (go-list m cs) (go m c)) (go m d) ℓ)]
                 [(? list? cs) (--> (go-list m cs) (go m d) ℓ)])]
              [(-->i cs d)
               (-->i (map go/dom cs) (go/dom d))]
              [(-struct/c t cs ℓ)
               (-struct/c t (go-list m cs) ℓ)]
              [_
               ;(printf "unchanged: ~a @ ~a~n" (show-e e) (show-subst m))
               e])]))
        (printf "go: ~a ~a -> ~a~n" (show-subst m) (show-e e) (show-e ans))))

    (go m e))

  (: e/ : Symbol -e -e → -e)
  (define (e/ x eₓ e) (e/map (hasheq x eₓ) e))

  (: remove-keys : Subst (℘ Symbol) → Subst)
  (define (remove-keys m xs)
    (for/fold ([m : Subst m]) ([x (in-set xs)])
      (hash-remove m x)))

  (: formals->names : -formals → (℘ Symbol))
  (define (formals->names xs)
    (cond
      [(-var? xs) (set-add (list->seteq (-var-init xs)) (-var-rest xs))]
      [else (list->seteq xs)]))

  (: first-forward-ref : (Listof -dom) → (Option Symbol))
  (define (first-forward-ref doms)
    (define-set seen : Symbol #:eq? #t #:as-mutable-hash? #t)
    (for/or : (Option Symbol) ([dom (in-list doms)])
      (match-define (-dom x ?xs _ _) dom)
      (seen-add! x)
      (and ?xs
           (for/or : (Option Symbol) ([x (in-list ?xs)] #:unless (seen-has? x))
             x))))
  )
