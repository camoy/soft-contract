#lang typed/racket/base

(provide Γ⊢e φs⊢e ⊢V p∋Vs
         plausible-φs-s? plausible-W? plausible-V-s?
         first-R)

(require racket/match
         racket/set
         racket/bool
         (only-in racket/list first second)
         (except-in racket/function arity-includes?)
         "../utils/main.rkt"
         "../primitives/utils.rkt"
         "../ast/main.rkt"
         "../runtime/main.rkt"
         "result.rkt"
         (for-syntax
          racket/base racket/contract
          "../utils/pretty.rkt" 
          "../primitives/utils.rkt"))

;; Syntax generation for checking whether argument satisfies predicate
(begin-for-syntax

  ;; Inspect inner application to see if it satisfies predicate
  (define/contract (generate-app-clauses p zs)
    (identifier? identifier? . -> . (listof syntax?))
    (define ⊢e (datum->syntax zs '⊢e))
    (define p⇒p (datum->syntax zs 'p⇒p))

    (for/list ([(o o-rng) prim-ranges])

      ;; Default case: application's range matches predicate exactly
      (define main-clause #`[(#,o-rng) '✓])
      
      ;; Refined cases: predicate is more refined than application's coarsest range
      (define/contract refined-clauses (listof syntax?)
        (for/list ([(o-rng* o-doms) (hash-ref prim-refinements-for-ranges o (hasheq))])
          
          (define/contract args (listof identifier?)
            (for/list ([(_ i) (in-indexed o-doms)])
              (datum->syntax #f (format-symbol "x~a" (n-sub i)))))
          
          (define/contract preconds (listof syntax?)
            (for/list ([dom o-doms] [arg args])
              #`(eq? '✓ (#,⊢e (-@ '#,dom (list #,arg) +ℓ₀)))))
          
          #`[(#,o-rng*)
             (match #,zs
               [(list #,@args) (if (and #,@preconds) '✓ '?)]
               [_ '?])]))

      (define rhs
        (cond
          [(null? refined-clauses)
           #`(#,p⇒p '#,o-rng #,p)]
          [else
           #`(match (#,p⇒p '#,o-rng #,p)
               ['?
                (case #,p
                  #,@refined-clauses
                  [else '?])]
               [ans ans])]))
      #`[(#,o) #,rhs])))

;; Check whether predicate excludes boolean
(define boolean-excludes? : (Symbol → Boolean)
  (set->predicate (hash-ref exclusions 'boolean?)))

(: ⊢e : -e → -R)
;; Check if expression returns truth
(define (⊢e e)
  (match e
    [(-b b) (if b '✓ '✗)]
    [(? -•?) '?]
    [(? -v?) '✓]
    [(-@ f xs _) (⊢@ f xs)]
    [_ '?]))

(: ⊢@ : -e (Listof -e) → -R)
  ;; Check if application returns truth
(define (⊢@ p xs)

  ;; generate clauses checking if `(p xs)` returns truth
  (define-syntax (generate-predicate-clauses stx)
    (define ans
      #`(match xs
          [(list (? -b? b))
           (match (-?@ p b)
             [(-b x) (decide-R (and x #|force boolean|# #t))]
             [_ '?])]
          [(list (-@ o zs _))
           (case o
             #,@(generate-app-clauses #'p #'zs)
             [else
              (cond
                [(and (-st-mk? o) (base? p)) '✗]
                [else '?])])]
          [_ '?]))
    ;(printf "generated:~n~a~n" (pretty (syntax->datum ans)))
    ans)

  (match p
    [(? -st-mk?) '✓]
    [(-st-p si)
     (match xs
       [(list (-@ (-st-mk sj) _ _)) ; TODO: No sub-struct for now.
        (decide-R (equal? si sj))]
       [(list (-b _)) '✗]
       [(list (-@ (? symbol? f) _ _))
        (cond ;; HACK for now
          [(hash-ref prim-ranges f #f)
           =>
           (λ ([f-rng : Symbol])
             (cond
               [(∋ (seteq 'integer? 'real? 'number? 'vector? 'boolean? 'not 'null?) f-rng) '✗]
               [else '?]))]
          [else '?])]
       [_ '?])]
    ['not (not-R (⊢e (car xs)))] ; assume right arity
    ['any/c '✓]
    ['none/c '✗]
    [(or 'equal? '=)
     (match xs
       [(list e₁ e₂)
        (match* (e₁ e₂)
          [((? -λ? v₁) (? -λ? v₂)) ; can't compare higher-order literals
           (if (equal? v₁ v₂) '? '✗)]
          [((? -•?) _) '?]
          [(_ (? -•?)) '?]
          [((? -v? v₁) (? -v? v₂)) (decide-R (equal? v₁ v₂))]
          [((-x x) (-x y))
           (if (equal? x y) '✓ '?)]
          [((-@ f xs _) (-@ g ys _))
           ; lose precision. Don't need `f = g, x = y` to prove `f(x) = g(y)`
           (cond
             [(and
               (or
                (and (-λ? f) (equal? f g))
                (eq? '✓ (⊢e (-@ 'equal? (list f g) +ℓ₀))))
               (= (length xs) (length ys)))
              (define res
                (for/seteq: : (℘ -R) ([x xs] [y ys])
                  (⊢e (-@ 'equal? (list x y) +ℓ₀))))
              (cond
                [(or (set-empty? res) (equal? res {seteq '✓})) '✓]
                [(and (-st-mk? f) (∋ res '✗)) '✗]
                [else '?])]
             [else '?])]
          [(_ _) (if (equal? e₁ e₂) '✓ '?)])]
       [_ #|TODO|# '?])]
    ['positive?
     (⊢@ '> (list (car xs) (-b 0)))]
    ['negative?
     (⊢@ '< (list (car xs) (-b 0)))]
    [(? symbol?)
     (cond
       [(and (eq? p 'boolean?) (match? xs (list (-@ (? -st-p?) _ _)))) '✓]
       [(and (eq? p 'procedure?) (match? xs (list (or (? -λ?) (? -case-λ?))))) '✓]
       [(hash-ref prim-ranges p #f) =>
        (λ ([p-rng : Symbol])
          (cond
            [(boolean-excludes? p-rng) '✓]
            [else (generate-predicate-clauses)]))]
       [else '?])]
    
    [_ '?]))

(: Γ⊢e : -Γ -s → -R)
(define (Γ⊢e Γ s) (φs⊢e (-Γ-facts Γ) s))

(: φs⊢e : (℘ -e) -s → -R)
(define (φs⊢e φs e)

  (when (∋ φs -ff)
    ;; Rule `{… #f …} ⊢ e : ✓` is not always desirable, because
    ;; sometimes we want `{… #f …} ⊢ (¬ e) : ✓`, which means `{… #f …} ⊢ e : ✗`
    ;; This is a problem with precision rather than soundness, but I want
    ;; (obviously) inconsistent path-conditions to not exist in the first place.
    (error 'φs⊢e "Attempt to prove/refute with inconsistent path-condition"))

  (: e⊢e : -e -e → -R)
  ;; Check if `e₂` returns truth when `e₁` does
  (define (e⊢e e₁ e₂)
    (with-debugging/off
      ((ans)
       ;; (⊢e e₂) is not redundant, because this may be just a sub-exp of the original goal
       (case (⊢e e₁)
         [(✗) '✓]
         [else
          (match (⊢e e₂)
            ['?
             (match* (e₁ e₂)
               ; e ⇒ e
               [(e e) '✓]
               ; NOTE: Don't abuse "contrapositive"
               ; (¬e₁ ⊢ ¬e₂ : ✗) does not follow from (e₂ ⊢ e₁ : ✗)
               [((-not e₁*) (-not e₂*))
                (case (e⊢e e₂* e₁*)
                  [(✓)   '✓]
                  [(✗ ?) '?])]
               [(e₁ (-not e₂*))
                (not-R (e⊢e e₁ e₂*))]
               [((-@ (? -v? p) (list e) _) (-@ (? -v? q) (list e) _))
                (p⇒p p q)] ; FIXME
               [((-@ (? -o? p) (list e) _) e)
                (cond
                  [(eq? 'not p) '✗]
                  [(and (symbol? p) (boolean-excludes? p)) '✓]
                  [(-st-p? p) '✓]
                  [else '?])]
               [((-@ (or '= 'equal?) (list e₁ e₂) _) (-@ (? -o? p) (list e₁) _))
                (⊢@ p (list e₂))]
               [((-@ (or '= 'equal?) (list e₁ e₂) _) (-@ (? -o? p) (list e₂) _))
                (⊢@ p (list e₁))]
               [((-@ (or '= 'equal?) (list e (-b b₁)) _)
                 (-@ (or '= 'equal?) (list e (-b b₂)) _))
                (decide-R (equal? b₁ b₂))]
               [((-@ (or '= 'equal?) (list (-b b₁) e) _)
                 (-@ (or '= 'equal?) (list (-b b₂) e) _))
                (decide-R (equal? b₁ b₂))]
               [(_ _) '?])]
            [R R])]))
      (printf "~a ⊢ ~a : ~a~n" (show-e e₁) (show-e e₂) ans)))

  (with-debugging/off
    ((ans)
     (cond
       [e
        (first-R
         (⊢e e)
         (match e
           [_ #:when (∋ φs       e ) '✓]
           [_ #:when (∋ φs (-not e)) '✗]
           [(-not e*) #:when (∋ φs e*) '✗]
           [else '?])
         (for*/fold ([R : -R '?])
                    ([φ φs] #:when (eq? '? R)
                     [R* (in-value (e⊢e φ e))])
           R*)
         '?)]
       [else '?]))
    (printf "~a ⊢ ~a : ~a~n" (set-map φs show-e) (show-s e) ans)))

(define (plausible-φs-s? [φs : (℘ -e)] [s : -s]) : Boolean
  (with-debugging/off
    ((a) (not (eq? '✗ (φs⊢e φs s))))
    (printf "plausible-φs-s: ~a ⊢ ~a : ~a~n"
            (set-map φs show-e)
            (show-s s)
            a)))

(: plausible-W? : (℘ -e) (Listof -V) -s → Boolean)
;; Check if value(s) `Vs` can instantiate symbol `s` given path condition `φs`
;; - #f indicates a definitely bogus case
;; - #t indicates (conservative) plausibility
(define (plausible-W? φs Vs s)
  (match* (Vs s)
    [(_ (-@ 'values es _))
     (and (= (length Vs) (length es))
          (for/and : Boolean ([V Vs] [e es])
            (plausible-V-s? φs V e)))]
    [((list V) _) #:when s
     (plausible-V-s? φs V s)]
    [(_ (or (? -v?) (-@ (? -prim?) _ _))) #f] ; length(Vs) ≠ 1, length(s) = 1
    [(_ _) #t]))

(: plausible-V-s? : (℘ -e) -V -s → Boolean)
(define (plausible-V-s? φs V s)
  (define-syntax-rule (with-prim-checks p? ...)
    (cond
      [s
       (match V
         ['undefined ; (ugly) This needs to come before (? -o?) ; TODO obsolete?
          (cond
            [(-v? s) #f]
            [else
             (case (φs⊢e φs (-?@ 'defined? s))
               [(✗ ?) #t]
               [(✓)   #f])])]
         [(or (-St si _) (-St* si _ _ _)) #:when si
          (plausible-φs-s? φs (-?@ (-st-p si) s))]
         [(or (? -Vector?) (? -Vector/hetero?) (? -Vector/homo?))
          (plausible-φs-s? φs (-?@ 'vector? s))]
         [(or (? -Clo?) (? -Case-Clo?) (? -Ar?) (? -o?))
          (plausible-φs-s? φs (-?@ 'procedure? s))]
         [(-b (? p?))
          (and (plausible-φs-s? φs (-?@ 'equal? s V))
               (implies (-b? s) (equal? V s)))] ...
         [(or (? -=>_?) (? -St/C?) (? -x/C?))
          (for/and : Boolean ([p : -o '(procedure? p? ...)])
            (case (φs⊢e φs (-?@ p s))
              [(✓)   #f]
              [(✗ ?) #t]))]
         [(-b (list))
          (plausible-φs-s? φs (-?@ 'null? s))]
         [(? -v? v)
          (plausible-φs-s? φs (-?@ 'equal? s v))]
         [(-● ps)
          (not (for/or : Boolean ([p ps])
                 (match p
                   [(? -o? o) (equal? '✗ (φs⊢e φs (-@ o (list s) +ℓ₀)))]
                   [(-λ (list x) e) (equal? '✗ (φs⊢e φs (e/ (-x x) s e)))]
                   [_ #f])))]
         [_ #t])]
      [else #t]))
  
  ;; order matters for precision, in the presence of subtypes
  (with-debugging/off ((ans) (with-prim-checks integer? real? number? string? symbol? keyword? not boolean?))
    (printf "plausible-V-s: ~a ⊢ ~a : ~a -> ~a~n" (set-map φs show-φ) (show-V V) (show-s s) ans)))

(: ⊢V : -V → -R)
;; Check if value represents truth
(define ⊢V
  (match-lambda
    [(-b #f) '✗]
    [(-● ps)
     (or (for/or : (U #f '✓ '✗) ([p ps] #:when (-v? p))
           (case (p⇒p p 'not)
             [(✓) '✗]
             [(✗) '✓]
             [(?) #f]))
         '?)]
    [_ '✓]))

(: p∋Vs : -V -V * → -R)
;; Check if value satisfies predicate
(define (p∋Vs p . Vs)
  
  (define (check-proc-arity-1 [V : -V]) : -R
    (match (p∋Vs 'procedure? V)
      ['✓ (decide-R (arity-includes? (assert (V-arity V)) 1))]
      [ans ans]))

  (with-debugging/off
    ((ans)
     (match Vs
       [(list (-● ps)) #:when (-v? p)
        (or (for/or : (U #f '✓ '✗) ([q ps] #:when (-v? q))
              (case (p⇒p q p)
                [(✓) '✓]
                [(✗) '✗]
                [(?) #f]))
            (case p ; special hacky cases where `q` is implied by 2+ predicates
              [(exact-nonnegative-integer?)
               (cond
                 [(and (∋ ps 'integer?)
                       (for/or : Boolean ([p ps])
                         (match?
                          p
                          (-λ (list x)
                              (-@ (or '< '<=)
                                  (list (-b (? (λ ([b : Base])
                                                 (and (real? b) (<= b 0)))))
                                        (-x x))
                                  _)))))
                  '✓]
                 [(and (∋ ps 'integer?)
                       (for/or : Boolean ([p ps])
                         (match?
                          p
                          (-λ (list x)
                              (-@ '<
                                  (list (-x x)
                                        (-b (? (λ ([b : Base])
                                                 (and (real? b) (<= 0 b))))))
                                  _)))))
                  '✗]
                 [(and (∋ ps 'integer?)
                       (for/or : Boolean ([p ps])
                         (match?
                          p
                          (-λ (list x)
                              (-@ '<=
                                  (list (-x x)
                                        (-b (? (λ ([b : Base])
                                                 (and (real? b) (< 0 b))))))
                                  _)))))
                  '✗]
                 [else '?])]
              [else '?]))]
       [_
        (match p
          [(? -st-mk?) '✓]
          [(? -st-mut?) '✓]
          [(? -st-ac?) '✓]
          [(-st-p si)
           (match Vs
             [(list (or (-St sj _) (-St* sj _ _ _)))
              ;; TODO: no sub-struct for now. May change later.
              (decide-R (equal? si (assert sj)))]
             [(list (-● ps))
              (or (for/or : (U '✓ '✗ #f) ([p ps] #:when (-st-p? p))
                    (match-define (-st-p s) p)
                    (decide-R (equal? s si)))
                  '?)]
             [_ '✗])]
          [(-Ar _ (or (? -o? o) (-α.def (-𝒾 (? -o? o) 'Λ)) (-α.wrp (-𝒾 (? -o? o) 'Λ))) _)
           #:when o
           (apply p∋Vs o Vs)]
          [(? symbol?)
           (case p
             ;; Insert manual rules here
             [(procedure?)
              (match Vs
                [(list (-● _)) '?]
                [(list (or (? -o?) (? -Clo?) (? -Case-Clo?) (? -Ar?) (? -Not/C?))) '✓]
                [(list (or (-And/C flat? _ _) (-Or/C flat? _ _) (-St/C flat? _ _))) (decide-R flat?)]
                [_ '✗])]
             [(vector?)
              (match Vs
                [(list (-● _)) '?]
                [(list (or (? -Vector?) (? -Vector/hetero?) (? -Vector/homo?))) '✓]
                [_ '✗])]
             [(contract?)
              (match Vs
                [(list (or (? -=>_?) (? -And/C?) (? -Or/C?) (? -Not/C?)
                           (? -Vectorof?) (? -Vector/C?) (? -St/C?) (? -x/C?))) '✓]
                [(list V) (check-proc-arity-1 V)]
                [_ '?])]
             [(flat-contract?)
              (match Vs
                [(list V) (check-proc-arity-1 V)]
                [_ '?])]
             [(any/c) '✓]
             [(none/c) '✗]
             [(arity-includes?)
              (match Vs
                [(list (-b (? Arity? a)) (-b (? Arity? b)))
                 (decide-R (arity-includes? a b))]
                [_ '?])]
             [(immutable?) ;; always true for now because no support for immutable vectors
              (match Vs
                [(list (? -●?)) '?]
                [_ '✗])]
             [(< <=) ; FIXME i may get the boundaries wrong
              (match Vs
                [(list (-● ps) (-b (? real? b)))
                 (match (set->list ps)
                   [(list _ ...
                          (-λ (list x) (-@ (or '< '<=) (list (-x x) (-b (? real? a))) _))
                          _ ...)
                    (if (<= a b) '✓ '?)]
                   [(list _ ...
                          (-λ (list x) (-@ (or '< '<=) (list (-b (? real? a)) (-x x)) _))
                          _ ...)
                    (if (> a b) '✗ '?)]
                   [_ '?])]
                [(list (-b (? real? b)) (-● ps))
                 (match (set->list ps)
                   [(list _ ...
                          (-λ (list x) (-@ (or '< '<=) (list (-x x) (-b (? real? a))) _))
                          _ ...)
                    (if (< a b) '✗ '?)]
                   [(list _ ...
                          (-λ (list x) (-@ (or '< '<=) (list (-b (? real? a)) (-x x)) _))
                          _ ...)
                    (if (>= a b) '✓ '?)]
                   [_ '?])]
                [_ '?])]
             [(>) (p∋Vs '< (second Vs) (first Vs))]
             [(>=) (p∋Vs '<= (second Vs) (first Vs))]
             ;; Default rules for operations on base values rely on simplification from `-?@`
             [else
              (cond
                [(hash-ref prim-ranges p #f) =>
                 (λ ([p-rng : Symbol]) : -R
                    (cond [(boolean-excludes? p-rng) '✓]
                          [else
                           (match Vs
                             [(list (? -b? bs) ...)
                              (match (apply -?@ p (cast bs (Listof -b)))
                                [(-b b) (decide-R (and b #|force boolean|# #t))]
                                [_ '?])]
                             [(list (? -●?) ...) '?]
                             [_ (cond [(and (base? p) (and (match? Vs (list (not (? -b?)))))) '✗]
                                      [else '?])])]))]
                [else '?])])]
          [_ '?])]))
    (printf "~a ∋ ~a: ~a~n" (show-V p) (map show-V Vs) ans)))

(: V≡ : -V -V → -R)
;; Check if 2 values are `equal?`
(define V≡
  (match-lambda**
   [((-b x₁) (-b x₂)) (decide-R (equal? x₁ x₂))]
   [(_ _) '?]))

(: p⇒p : -v -v → -R)
;; Return whether predicate `p` definitely implies or excludes `q`.
(define (p⇒p p q)
  (match* (p q)
    [(_ 'any/c) '✓]
    [('none/c _) '✓]
    [(_ 'none/c) '✗]
    [((? symbol? p) (? symbol? q))
     (cond [(∋ (hash-ref implications p →∅eq) q) '✓]
           [(∋ (hash-ref exclusions p →∅eq) q) '✗]
           [else '?])]
    [(p 'values)
     (case p
       [(not) '✗]
       [(any/c) '?]
       [else '✓])]
    [((-st-p si) (-st-p sj))
     ;; TODO: no sub-struct for now. Probably changes later
     (decide-R (equal? si sj))]

    ;; Special rules for reals
    ; 
    [(_ 'positive?)
     (p⇒p p (-λ '(𝒙) (-@ '< (list (-b 0) (-x '𝒙)) +ℓ₀)))]
    [(_ 'negative?)
     (p⇒p p (-λ '(𝒙) (-@ '< (list (-x '𝒙) (-b 0)) +ℓ₀)))]
    [('positive? _)
     (p⇒p (-λ '(𝒙) (-@ '< (list (-b 0) (-x '𝒙)) +ℓ₀)) q)]
    [('negative? _)
     (p⇒p (-λ '(𝒙) (-@ '< (list (-x '𝒙) (-b 0)) +ℓ₀)) q)]
    ;
    [((-λ (list x) (-@ (and o (or '<= '<)) (list (-b (? real? a)) (-x x)) _))
      (-λ (list y) (-@ o                   (list (-b (? real? b)) (-x y)) _)))
     (if (>= a b) '✓ '?)]
    [((-λ (list x) (-@ (and o (or '<= '<)) (list (-x x) (-b (? real? a))) _))
      (-λ (list y) (-@ o                   (list (-x y) (-b (? real? b))) _)))
     (if (<= a b) '✓ '?)]
    ;
    [((-λ (list x) (-@ '< (list (-x x) (-b (? real? b))) _)) 'zero?)
     (if (<= b 0) '✗ '?)]
    [((-λ (list x) (-@ '<= (list (-x x) (-b (? real? b))) _)) 'zero?)
     (if (< b 0) '✗ '?)]
    [((-λ (list x) (-@ '< (list (-b (? real? b)) (-x x)) _)) 'zero?)
     (if (>= b 0) '✗ '?)]
    [((-λ (list x) (-@ '<= (list (-b (? real? b)) (-x x)) _)) 'zero?)
     (if (> b 0) '✗ '?)]
    
    ;; default
    [(_ _)
     (cond [(or (and (symbol? p) (hash-has-key? implications p) (-st-p? q))
                (and (symbol? q) (hash-has-key? implications q) (-st-p? p)))
            '✗]
           [else '?])]))

(module+ test
  (require typed/rackunit
           "../ast/definition.rkt"
           "../runtime/main.rkt"
           "for-test.rkt")
  
  ;; V ∈ p
  #|(check-✓ (p∋Vs 'not (-b #f)))
  (check-✓ (p∋Vs 'boolean? (-b #f)))
  (check-✓ (p∋Vs 'integer? (-b 1)))
  (check-✓ (p∋Vs 'real? (-b 1)))
  (check-✓ (p∋Vs 'number? (-b 1)))
  (check-✓ (p∋Vs 'procedure? (-Clo '(x) (λ _ (⊥ans)) ⊥ρ ⊤Γ)))
  (check-✓ (p∋Vs 'procedure? 'procedure?))
  (check-✓ (p∋Vs -cons? (-St -s-cons (list (-α.fld -𝒾-cons 0 0 0) (-α.fld -𝒾-cons 0 0 1)))))
  (check-✗ (p∋Vs 'number? (-St -s-cons (list (-α.fld -𝒾-cons 0 0 0) (-α.fld -𝒾-cons 0 0 1)))))
  (check-✗ (p∋Vs 'integer? (-b 1.5)))
  (check-✗ (p∋Vs 'real? (-b 1+1i)))
  (check-? (p∋Vs 'integer? -●/V))|#

  ;; ⊢ e
  #|(check-✓ (φs⊢e ∅ 'not))
  (check-✓ (φs⊢e ∅ (-b 0)))
  (check-✗ (φs⊢e ∅ (-b #f)))
  (check-? (φs⊢e ∅ (-x 'x)))
  (check-✗ (φs⊢e ∅ (-?@ 'not (-b 0))))
  (check-✓ (φs⊢e ∅ (-?@ 'equal? (-x 'x) (-x 'x))))
  (check-✓ (φs⊢e ∅ (-?@ '+ (-x 'x) (-x 'y))))
  (check-✗ (φs⊢e ∅ (-?@ -cons? -null)))
  (check-✗ (φs⊢e ∅ (-?@ 'null? (-?@ -cons (-b 0) (-b 1)))))|#
  
  ;; Γ ⊢ e
  (check-✓ (φs⊢e {set (assert (-?@ -cons? (-x 'x)))} (-x 'x)))
  (check-✓ (φs⊢e {set (assert (-?@ 'integer? (-x 'x)))} (-?@ 'real? (-x 'x))))
  (check-✓ (φs⊢e {set (assert (-?@ 'not (-?@ 'number? (-x 'x))))} (-?@ 'not (-?@ 'integer? (-x 'x)))))
  (check-✗ (φs⊢e {set (assert (-?@ 'not (-x 'x)))} (-x 'x)))
  (check-? (φs⊢e {set (assert (-?@ 'number? (-x 'x)))} (-?@ 'integer? (-x 'x))))

  ;; plausibility
  (check-false (plausible-W? ∅ (list (-b 1)) (-b 2)))
  (check-false (plausible-W? ∅ (list (-b 1) (-b 2)) (-b 3)))
  (check-false (plausible-W? ∅ (list (-b 1) (-b 2)) (-?@ 'values (-b 1) (-b 3))))
  (check-false (plausible-W? ∅ (list -tt) -ff))
  (check-true  (plausible-W? ∅ (list -tt) -tt))
  (check-false (plausible-W? {set (assert (-not (-x 'x)))} (list (-b 0)) (-x 'x)))
  )
