#lang typed/racket/base

(provide (for-syntax (all-defined-out)))

(require (for-syntax racket/base
                     (only-in typed/racket/base index?)
                     racket/syntax
                     racket/match
                     racket/list
                     racket/function
                     racket/contract
                     racket/pretty
                     syntax/parse
                     syntax/parse/define
                     "def-utils.rkt"
                     (only-in "../utils/pretty.rkt" n-sub))
         racket/contract
         racket/list
         racket/match
         racket/set
         racket/splicing
         racket/promise
         syntax/parse/define
         set-extras
         "../utils/map.rkt"
         "../ast/signatures.rkt"
         "../runtime/signatures.rkt")

(begin-for-syntax

  (define-syntax-rule (with-hack:make-available (src id ...) e ...)
    (with-syntax ([id (format-id src "~a" 'id)] ...) e ...))

  (define-syntax-rule (hack:make-available src id ...)
    (begin (define/with-syntax id (format-id src "~a" 'id)) ...))

  ;; Global parameters that need to be set up for each `def`
  (define-parameter/contract
    ; identifiers available to function body
    [-o identifier? #f]
    [-ℓ identifier? #f]
    [-Ws identifier? #f]
    [-⟪ℋ⟫ identifier? #f]
    [-$ identifier? #f]
    [-Γ identifier? #f]
    [-Σ identifier? #f]
    [-⟦k⟧ identifier? #f]
    [-sig syntax? #f]
    [-Wⁿ (listof identifier?) #f]
    [-Wᵣ (or/c #f identifier?) #f]
    [-gen-lift? boolean? #f]
    [-refinements (listof syntax?) '()]
    )

  (define/contract (gen-cases)
    (-> (listof syntax?))

    (define arity-check-cases
      (let go ([sig (-sig)])
        (syntax-parse sig
          [((~literal ->) c ... d:d)
           (list (gen-clause (syntax->list #'(c ...))
                             (take (-Wⁿ) (syntax-length #'(c ...)))
                             #f
                             #f
                             (attribute d.values)))]
          [((~literal ->*) (c ...) #:rest r d:d)
           (list (gen-clause (syntax->list #'(c ...))
                             (take (-Wⁿ) (syntax-length #'(c ...)))
                             #'r
                             (-Wᵣ)
                             (attribute d.values)))]
          [((~literal case->) clauses ...)
           (for/list ([clause (in-syntax-list #'(clauses ...))])
             (syntax-parse clause
               [((~literal ->) c ... #:rest r d:d)
                (gen-clause (syntax->list #'(c ...))
                            (take (-Wⁿ) (syntax-length #'(c ...)))
                            #'r
                            (-Wᵣ)
                            (attribute d.values))]
               [((~literal ->) c ... d:d)
                (gen-clause (syntax->list #'(c ...))
                            (take (-Wⁿ) (syntax-length #'(c ...)))
                            #f
                            #f
                            (attribute d.values))]))]
          [((~literal ∀/c) _ c) (go #'c)])))
    
    (list
     #`(match #,(-Ws)
         #,@arity-check-cases
         [_
          (define blm (-blm (ℓ-src #,(-ℓ)) '#,(-o) (list 'error-msg) (map -W¹-V #,(-Ws)) #,(-ℓ)))
          (#,(-⟦k⟧) blm #,(-$) #,(-Γ) #,(-⟪ℋ⟫) #,(-Σ))])))

  (define/contract (gen-clause dom-inits arg-inits ?dom-rest ?arg-rest rngs)
    ((listof syntax?) (listof identifier?) (or/c #f syntax?) (or/c #f identifier?) (or/c #f (listof syntax?)) . -> . syntax?)
    (hack:make-available (-o) mon*.c∷ ?t@)
    (define/with-syntax (stx-dom-init-checks ...) (map gen-ctc dom-inits))
    (define/with-syntax stx-pat (if ?arg-rest #`(list* #,@arg-inits #,?arg-rest) #`(list #,@arg-inits)))
    (define/with-syntax stx-check-list
      (cond
        [?dom-rest
         (define dom-rest-elem
           (syntax-parse ?dom-rest
             [((~literal listof) c) #'c]
             [_ #'any/c]))
         #`(list* stx-dom-init-checks ...
                  (make-list (length #,?arg-rest) #,(gen-ctc dom-rest-elem)))]
        [else
         #'(list stx-dom-init-checks ...)]))

    #`[stx-pat
       (define t-args (map -W¹-t #,(-Ws)))
       (define t-ans (apply ?t@ '#,(-o) t-args))
       (define ⟦k⟧:gen-range
         #,(gen-range-refinements
            (if ?dom-rest (arity-at-least (length dom-inits)) (length dom-inits))
            rngs
            #'t-ans
             (gen-range-wrap rngs #'t-ans (-⟦k⟧))))
       (define ⟦k⟧:chk-args (mon*.c∷ (-ctx (ℓ-src #,(-ℓ)) '#,(-o) '#,(-o) #,(-ℓ))
                                     stx-check-list
                                     t-ans
                                     ⟦k⟧:gen-range))
       (⟦k⟧:chk-args (-W (map -W¹-V #,(-Ws)) (apply ?t@ 'values t-args)) #,(-$) #,(-Γ) #,(-⟪ℋ⟫) #,(-Σ))])

  (define/contract (gen-range-wrap rngs tₐ k)
    ((or/c #f (listof syntax?)) identifier? identifier? . -> . syntax?)
    (hack:make-available (-o) bgn0.e∷ mon*.c∷ ⊥ρ +●)
    (if (?flatten-range rngs)
        k
        (with-syntax ([ctx #`(-ctx '#,(-o) (ℓ-src #,(-ℓ)) '#,(-o) #,(-ℓ))])
          #`(mon*.c∷ ctx (list #,@(map gen-ctc rngs)) #,tₐ #,k))))

  (define/contract (gen-range-refinements case-arity rngs tₐ k)
    ((or/c exact-nonnegative-integer? arity-at-least?) (or/c #f (listof syntax?)) identifier? syntax? . -> . syntax?)
    (hack:make-available (-o) maybe-refine∷ +●)
    (define compatible-refinements
      (filter (syntax-parser
                [r:mono-hc (arity-compatible? case-arity (attribute r.arity))])
              (-refinements)))
    (define/with-syntax (refinement-cases ...)
      (for/list ([ref (in-list compatible-refinements)])
        (syntax-parse ref
          [((~literal ->) c ... d)
           (define/with-syntax (C ...) (map gen-ctc-V (syntax->list #'(c ...))))
           (define/with-syntax D (gen-rng-V #'d))
           #`(list (list C ...) #f D)]
          [((~literal ->*) (c ...) #:rest r d)
           (define/with-syntax (C ...) (map gen-ctc-V (syntax->list #'(c ...))))
           (define/with-syntax R
             (syntax-parse #'r
               [((~literal listof) c) (gen-ctc-V #'c)]
               [_ #''any/c]))
           (define/with-syntax D (gen-rng-V #'d))
           #`(list (list C ...) R D)])))
    (define/with-syntax (V ...)
      (match (?flatten-range rngs)
        ['any
         (printf "warning: arbitrarily generate 1 value for range `any` in `~a`~n" (syntax-e (-o)))
         (list #'(+●))]
        [#f (make-list (length rngs) #`(+●))]
        [initial-refinements
         (for/list ([cs (in-list initial-refinements)])
           (define/with-syntax (c ...) cs)
           #'(+● 'c ...))]))
    #`(maybe-refine∷ (list refinement-cases ...) (-W (list V ...) #,tₐ) #,k))

  ;; See if range needs to go through general contract monitoring
  (define/contract (?flatten-range rngs)
    ((or/c #f (listof syntax?)) . -> . (or/c #f 'any (listof syntax?)))
    (define flatten-rng
      (syntax-parser
        [c:o #'(c)]
        [((~literal and/c) c:o ...) #'(c ...)]
        [_ #f]))
    (case rngs
      [(#f) 'any]
      [else
       (define flattens (map flatten-rng rngs))
       (and (andmap values flattens) flattens)]))

  (define/contract (gen-ctc c)
    (syntax? . -> . syntax?)
    (hack:make-available (-o) +⟪α⟫ℓ₀)
    #`(+⟪α⟫ℓ₀ #,(gen-ctc-V c)))

  (define/contract (gen-ctc-V c)
    (syntax? . -> . syntax?)
    (hack:make-available (-o) +⟪α⟫ℓ₀)
    (define/contract ((go* Comb/C base/c) cs)
      (identifier? syntax? . -> . ((listof syntax?) . -> . (values syntax? boolean?)))
      (match cs
        ['() (values base/c #t)]
        [(list c) (values (gen-ctc-V c) (c-flat? c))]
        [(cons c cs*)
         (define-values (Cᵣ r-flat?) ((go* Comb/C base/c) cs*))
         (define Cₗ (gen-ctc-V c))
         (define flat? (and (c-flat? c) r-flat?))
         (values #`(#,Comb/C #,flat? (+⟪α⟫ℓ₀ #,Cₗ) (+⟪α⟫ℓ₀ #,Cᵣ)) flat?)]))

    (syntax-parse c
      [o:o #''o]
      [l:lit #'(-≡/c l)]
      [((~literal not/c) c*)
       (define V* (gen-ctc-V #'c*))
       #`(-Not/C #,(gen-ctc V*))]
      [(o:cmp r:number)
       (syntax-parse #'o
         [(~literal >/c)  #'(->/c r)]
         [(~literal </c)  #'(-</c r)]
         [(~literal >=/c) #'(-≥/c r)]
         [(~literal <=/c) #'(-≤/c r)]
         [(~literal =/c)  #'(-=/c r)])]
      [((~literal ->) c ... d)
       (define Cs (map gen-ctc (syntax->list #'(c ...))))
       (define D  (gen-rng #'d))
       #`(-=> (list #,@Cs) #,D +ℓ₀)]
      [((~literal ->*) (c ...) #:rest r d)
       (define Cs (map gen-ctc (syntax->list #'(c ...))))
       (define R (gen-ctc #'r))
       (define D (gen-rng #'d))
       #`(-=> (-var (list #,@Cs) #,R) #,D +ℓ₀)]
      [((~literal case->) clauses ...)
       (error 'gen-ctc "TODO: nested case->")]
      [((~literal ∀/c) (x ...) c)
       (error 'gen-ctc "TODO: nested ∀/c")]
      [((~literal and/c) c ...)
       (define-values (V _) ((go* #'-And/C #''any/c) (syntax->list #'(c ...))))
       V]
      [((~literal or/c) c ...)
       (define-values (V _) ((go* #'-Or/C #''none/c) (syntax->list #'(c ...))))
       V]
      [((~literal cons/c) c d)
       #`(-St/C #,(and (c-flat? #'c) (c-flat? #'d)) -𝒾-cons (list #,(gen-ctc #'c) #,(gen-ctc #'d)))]
      [((~literal listof) c)
       (error 'gen-ctc "TODO: listof")]
      [((~literal list/c) c ...)
       (gen-ctc-V (foldr (λ (c d) #`(cons/c #,c #,d)) #'null? (syntax->list #'(c ...))))]
      [((~literal vectorof) c)
       #`(-Vectorof #,(gen-ctc #'c))]
      [((~literal vector/c) c ...)
       #`(-Vector/C (list #,@(map gen-ctc (syntax->list #'(c ...)))))]
      [((~literal set/c) c)
       (error 'gen-ctc "TODO: set/c")]
      [((~literal hash/c) c)
       (error 'gen-ctc "TODO: hash/c")]
      [_
       #`(error 'gen-ctc "TODO ~a" '#,c)]))

  (define/contract gen-rng (syntax? . -> . syntax?)
    (syntax-parser
      [((~literal values) c ...) #`(list #,@(map gen-ctc (syntax->list #'(c ...))))]
      [(~literal any) #''any]
      [c #`(list #,(gen-ctc #'c))]))

  (define/contract gen-rng-V (syntax? . -> . syntax?)
    (syntax-parser
      [((~literal values) c ...) #`(list #,@(map gen-ctc-V (syntax->list #'(c ...))))]
      [(~literal any) #''any]
      [c #`(list #,(gen-ctc-V #'c))]))
  )
