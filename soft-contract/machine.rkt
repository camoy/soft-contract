#lang typed/racket/base
(require
 racket/match racket/set racket/list racket/bool racket/function
 "utils.rkt" "lang.rkt" "runtime.rkt" "show.rkt" "provability.rkt")
(require/typed "parse.rkt"
  [files->prog ((Listof Path-String) → -prog)])

(provide (all-defined-out)) ; TODO

;; Continuation frames
(define-data -φ
  (struct -φ.if [t : -E] [e : -E])
  (struct -φ.let-values
    [pending : (Listof Symbol)]
    [bnds : (Listof (Pairof (Listof Symbol) -e))]
    [bnds↓ : (Map Symbol -WV)]
    [env : -ρ]
    [body : -e]
    [ctx : Mon-Party])
  (struct -φ.letrec-values
    [pending : (Listof Symbol)]
    [bnds : (Listof (Pairof (Listof Symbol) -e))]
    [env : -ρ]
    [body : -e]
    [ctx : Mon-Party]
    [old-dom : (Setof Symbol)])
  (struct -φ.set! [α : -α])
  (struct -φ.@ [es : (Listof -E)] [vs : (Listof -WV)] [ctx : Mon-Party])
  (struct -φ.begin [es : (Listof -e)] [env : -ρ])
  (struct -φ.begin0v [es : (Listof -e)] [env : -ρ])
  (struct -φ.begin0e [V : -WVs] [es : (Listof -e)] [env : -ρ])
  (struct -φ.mon.v [ctc : (U -E -WV)] [mon-info : Mon-Info])
  (struct -φ.mon.c [val : (U -E -WV)] [mon-info : Mon-Info])
  (struct -φ.indy.dom
    [pending : Symbol]
    [doms : (Listof (Pairof Symbol -WV))]
    [args : (Listof -WV)]
    [args↓ : (Listof (Pairof Symbol -WV))]
    [fun : -V]
    [rng : -↓]
    [mon-info : Mon-Info])
  (struct -φ.indy.rng [fun : -V] [args : (Listof -WV)] [min-info : Mon-Info])
  (struct -φ.rt [Γ : -Γ] [e : -?e])
  (struct -φ.rt.dom [old : (Setof Symbol)])
  ;; contract stuff
  (struct -φ.μc [x : Symbol])
  (struct -φ.struct/c
    [name : -id] [fields : (Listof -e)] [env : -ρ] [fields↓ : (Listof -WV)])
  (struct -φ.=> [dom : (Listof -e)] [dom↓ : (Listof -WV)] [env : -ρ])
  (struct -φ.=>i
    [dom : (Listof -e)] [dom↓ : (Listof -WV)] [xs : (Listof Symbol)] [rng : -e] [env : -ρ])
  )

;; Stack address
(struct -τ ([E : (U -E #|HACK|# (Listof (U Symbol -E)))] [Γ : -Γ]) #:transparent)
;; Stack
(struct -κ ([top : -φ] [nxt : -τ]) #:transparent)

(define-type -Ξ (MMap -τ -κ))

;; (narrow) state
(struct -ς ([e : -E] [Γ : -Γ] [τ : -τ] [σ : -σ] [Ξ : -Ξ] [M : -M]) #:transparent)

(define-type -ς* (U -ς (Setof -ς)))

(: 𝑰 : -prog → -ς)
;; Load program to intial machine state
;; FIXME: allow expressions in top-levels and execute them instead,
;;        then initialize top-levels to `undefined`
(define (𝑰 p)
  (match-define (-prog ms e₀) p)

  (: alloc-es : -σ (Listof -e) → (Values -σ (Listof -α)))
  (define (alloc-es σ es)
    (define-values (σ* αs-rev)
      (for/fold ([σ* : -σ σ] [αs-rev : (Listof -α) '()])
                ([e es])
        (define-values (σ** V) (alloc-e σ* e))
        (define α (-α.val e))
        (values (⊔ σ** α V) (cons α αs-rev))))
    (values σ* (reverse αs-rev)))

  (: alloc-e : -σ -e → (Values -σ -V))
  (define (alloc-e σ e)
    (match e
      [(? -v?) (values σ (close e -ρ∅ -Γ∅))]
      [(--> doms rng)
       (define-values (σ₁ α)
         (let-values ([(σ* V) (alloc-e σ rng)])
           (define α (-α.val rng))
           (values (⊔ σ* α V) α)))
       (define-values (σ₂ γs) (alloc-es σ₁ doms))
       (values σ₂ (-=> γs α))]
      [(-->i doms rng)
       (define-values (xs cs)
         (for/lists ([xs : (Listof Symbol)] [cs : (Listof -e)])
                    ([dom doms])
           (values (car dom) (cdr dom))))
       (define-values (σ* γs) (alloc-es σ cs))
       (values σ* (-=>i (map (inst cons Symbol -α) xs γs) rng -ρ∅ -Γ∅))]
      [(-@ (-st-mk (-id (and t (or 'and/c 'or/c 'not/c)) 'Λ) _) cs _)
       (define-values (σ* αs) (alloc-es σ cs))
       (values σ* (-St (-id t 'Λ) αs))]
      [(-struct/c id cs)
       (define-values (σ* αs) (alloc-es σ cs))
       (values σ* (-St/C id αs))]
      [e (error '𝑰 "TODO: execute general expression. For now can't handle ~a"
                (show-e σ e))]))

  ;; Assuming each top-level variable binds a value for now.
  ;; TODO generalize.
  (define σ₀
    (for*/fold ([σ : -σ -σ∅])
               ([m ms]
                [form (-plain-module-begin-body (-module-body m))])
      (define mod-path (-module-path m))
      (match form
        ;; general top-level form
        [(? -e?) σ]
        [(-define-values ids e)
         (cond
           [(= 1 (length ids))
            (define-values (σ* V) (alloc-e σ e))
            (⊔ σ* (-α.def (-id (car ids) mod-path)) V)]
           [else
            (error '𝑰 "TODO: general top-level. For now can't handle `define-~a-values`"
                   (length ids))])]
        [(? -require?) σ]
        ;; provide
        [(-provide specs)
         (for/fold ([σ : -σ σ]) ([spec specs])
           (match-define (-p/c-item x c) spec)
           (define-values (σ₁ C) (alloc-e σ c))
           (define id (-id x mod-path))
           (define σ₂ (⊔ σ₁ (-α.ctc id) C))
           (cond
             [(hash-has-key? σ₂ (-α.def id)) σ₂]
             [else (⊔ σ₂ (-α.def id) '•)]))]
        ;; submodule-form
        [(? -module?) (error '𝑰 "TODO: sub-module forms")])))

  (define E₀ (-↓ e₀ -ρ∅))
  (define τ₀ (-τ E₀ -Γ∅))

  (-ς E₀ -Γ∅ τ₀ σ₀ (hash τ₀ ∅) (hash)))


(: τ↓ : (case-> [-e -ρ -Γ → -τ]
                [-E -Γ → -τ]))
;; Create a simplified stack address
(define τ↓
  (case-lambda
    [(e ρ Γ)
     (define FVs (FV e))
     (define ρ* (ρ↓ ρ FVs))
     (define Γ* (Γ↓ Γ FVs))
     (-τ (-↓ e ρ*) Γ*)]
    [(E Γ)
     (match E
       [(-↓ e ρ) (τ↓ e ρ Γ)]
       [_ (-τ E Γ)])]))

(: final-state? : -ς → Boolean)
(define final-state?
  (match-lambda
    [(-ς (-W (? list?) _) _ τ _ Ξ _)
     ;; Rely on the fact that there's no merging such that Ξ(τ₀) ≠ ∅
     (set-empty? (hash-ref Ξ τ))]
    [_ #f]))

(: final? (case-> [-ς → Boolean]
                  [-E -τ -Ξ → Boolean]))
(define final?
  (case-lambda
    [(E τ Ξ)
     (cond
       [(-blm? E) #t]
       [(-W? E) (set-empty? (hash-ref Ξ τ))]
       [else #f])]
    [(ς)
     (match-define (-ς E _ τ _ Ξ M) ς)
     (final? E τ Ξ)]))


#| Obsolete stuff. TODO: Delete.
(define-data .κ
  (struct .if/κ [t : .E] [e : .E])
  (struct .let-values/κ
    [pending-arity : Integer]
    [bnds : (Listof (Pairof Integer .expr))]
    [vals : (Listof .V)]
    [env : .ρ]
    [body : .expr]
    [ctx : Mon-Party])
  (struct .letrec-values/κ
    [pending-arity : Integer]
    [bnds : (Listof (Pairof Integer .expr))]
    [env : .ρ]
    [body : .expr]
    [ctx : Mon-Party])
  (struct .@/κ [e* : (Listof .E)] [v* : (Listof .V)] [ctx : Mon-Party])
  (struct .begin/κ [es : (Listof .expr)] [ρ : .ρ])
  (struct .begin0v/κ [es : (Listof .expr)] [ρ : .ρ])
  (struct .begin0e/κ [V : .V] [es : (Listof .expr)] [ρ : .ρ])
  (struct .▹/κ [ce : (U (Pairof #f .E) (Pairof .V #f))] [l³ : Mon-Info])
  (struct .indy/κ
    [c : (Listof .V)] [x : (Listof .V)] [x↓ : (Listof .V)]
    [d : (U #f .↓)] [v? : (U #f Integer)] [l³ : Mon-Info])
  ;; contract stuff
  (struct .μc/κ [x : Symbol])
  (struct .λc/κ [c : (Listof .expr)] [c↓ : (Listof .V)] [d : .expr] [ρ : .ρ] [v? : Boolean])
  (struct .structc/κ [t : .id] [c : (Listof .expr)] [ρ : .ρ] [c↓ : (Listof .V)])
  ;; magics for termination. `ce` does not use these
  (struct .rt/κ [σ : .σ] [f : .λ↓] [x : (Listof .V)])
  (struct .blr/κ [F : .F] [σ : .σ] [v : .V])
  (struct .recchk/κ [c : .μ/C] [v : .V]) ; where all labels are fully resolved
  ;p experiment
  (struct .μ/κ [F : .μ/V] [xs : (Listof .V)] [σ : .σ]))
(define-type .κ* (Listof .κ))

;; ctx in e's position for pending states
(struct .ς ([e : (U (Pairof .rt/κ .F) .E)] [s : .σ] [k : .κ*]) #:transparent)
(define-type .ς+ (Setof .ς))
(define-type .ς* (U .ς .ς+))

(: final? : .ς → Boolean)
(define (final? ς)
  (match? ς (.ς (? .blm?) _ _) (.ς (? .Vs?) _ (list))))

(: inj : .expr → .ς)
(define (inj e)
  (.ς (.↓ e ρ∅) σ∅ empty))

(define-syntax-rule (match/nd v [p e ...] ...) (match/nd: (.Ans → .ς) v [p e ...] ...))
(define-syntax-rule (match/nd/σ σ v [b e ...] ...)
  (match/nd: (.Ans → .ς) v [(cons σ (-Vs (.// (.b b) _))) e ...] ...))

(: and/ς : (Listof .E) .σ .κ* → .ς)
(define (and/ς E* σ k)
  (match E*
    ['() (.ς -VsTT σ k)]
    [(list E) (.ς E σ k)]
    [(cons E Er)
     (.ς E σ (foldr (λ ([Ei : .E] [k : .κ*]) (cons (.if/κ Ei -VsFF) k)) k Er))]))

(: or/ς : (Listof .E) .σ .κ* → .ς)
(define (or/ς E* σ k)
  (match E*
    ['() (.ς -VsFF σ k)]
    [(list E) (.ς E σ k)]
    [(cons E Er)
     (.ς E σ (foldr (λ ([Ei : .E] [k : .κ*]) (cons (.if/κ -VsTT Ei) k)) k Er))]))

(: ▹/κ1 : .V Mon-Info .κ* → .κ*)
(define (▹/κ1 C l³ k)

  (: trim : .κ* → .κ*)
  (define/match (trim k)
    [((cons (and κ (.▹/κ (cons (? .V? D) #f) _)) k*))
     (cond [(equal? '✓ (C⇒C C D)) (trim k*)]
           [else (cons κ (trim k*))])]
    [(_) k])
  
  (match C
    [(.// (.λ↓ (.λ 1 (.b #t)) _) _) k]
    [(.// (? .Λ/C?) _) (cons (.▹/κ (cons C #f) l³) k)]
    [_ (cons (.▹/κ (cons C #f) l³) (trim k))]))

(: show-κ : .σ .κ → Sexp)
(define (show-κ σ κ)
  (define E (curry show-E σ))
  (define V (curry show-V σ))
  (match κ
    [(.if/κ t e) `(if ∘ ,(E t) ,(E e))]
    [(? .let-values/κ?) '(let-values …)]
    [(.@/κ e* v* _) `(@ ,@(reverse (map V v*)) ∘ ,@(map E e*))]
    [(.▹/κ (cons #f (? .E? e)) _) `(∘ ▹ ,(E e))]
    [(.▹/κ (cons (? .V? C) #f) _) `(,(V C) ▹ ∘)]
    [(.indy/κ Cs xs xs↓ d _ _) `(indy ,(map V Cs) ,(map V xs) ,(map V xs↓)
                                      ,(match d [#f '_] [(? .E? d) (E d)]))]
    [(.μc/κ x) `(μ/c ,x ∘)]
    [(.λc/κ cs Cs d ρ _) `(λ/c (,@(reverse (map V Cs)) ,@(map (curry show-e σ) cs)) ,(show-e σ d))]
    [(.structc/κ t c _ c↓) `(struct/c ,(.id-name t) (,@(reverse (map V c↓)) ,(map (curry show-e σ) c)))]
    [(.rt/κ _ f x) `(rt ,(V (→V f)) ,@(map V x))]
    [(.blr/κ _ _ v) `(blr ,(V v))]
    [(.recchk/κ c v) `(μ/▹ ,(V (→V c)) ,(V v))]))

(: show-ek : .σ .κ* Sexp → Sexp)
(define (show-ek σ k acc)

  (for/fold ([acc : Sexp acc]) ([κ (in-list k)])
    (match κ
      [(.if/κ E₁ E₂) `(if ,acc ,(show-E σ E₁) ,(show-E σ E₂))]
      [(.let-values/κ _n bnds Vs _ρ e _ctx)
       `(let-values (,@(reverse (show-Vs σ Vs))
                     (□ ← ,acc)
                     ,@(for/list : (Listof Sexp) ([bnd bnds])
                         (show-e σ (cdr bnd))))
          ,(show-e σ e))]
      [(.letrec-values/κ _n bnds _ρ e _ctx)
       `(letrec-values (… (□ ← ,acc) ,@(for/list : (Listof Sexp) ([bnd bnds]) (show-e σ (cdr bnd))))
          ,(show-e σ e))]
      [(.@/κ Es Vs _ctx)
       `(,@(reverse (show-Vs σ Vs)) ,acc ,@(map (curry show-E σ) Es))]
      [(.begin/κ es _)
       `(begin ,acc ,@(map (curry show-e σ) es))]
      [(.begin0v/κ es _)
       `(begin0 ,acc ,@(map (curry show-e σ) es))]
      [(.begin0e/κ V es _)
       `(begin0 ,(show-V σ V) ,acc ,@(map (curry show-e σ) es))]
      [(.▹/κ ce _)
       (cond [(.E? (cdr ce)) `(mon ,acc ,(show-E σ (cdr ce)))]
             [(.V? (car ce)) `(mon ,(show-V σ (car ce)) ,acc)]
             [else (error 'Internal "show-ek: unexpected case")])]
      [(.indy/κ Cs Xs Xs↓ D _v? _)
       (cond
         [D
          `(mon ,(show-E σ D)
                (,@(reverse (show-Vs σ Xs↓))
                 ,acc
                 ,@(for/list : (Listof Sexp) ([Cᵢ Cs] [Vᵢ Xs])
                     `(mon ,(show-V σ Cᵢ) ,(show-V σ Vᵢ)))))]
         [else
          `(mon ,acc
                (,@(reverse (show-Vs σ Xs↓))
                 ,@(for/list : (Listof Sexp) ([Cᵢ Cs] [Vᵢ Xs])
                     `(mon ,(show-V σ Cᵢ) ,(show-V σ Vᵢ)))))])]
      [(.μc/κ x) `(μ/c ,x ,acc)]
      [(.λc/κ cs Cs d _ρ _)
       `(→i (,@(reverse (show-Vs σ Cs)) ,acc ,@(map (curry show-e σ) cs))
            ,(show-e σ d))]
      [(.structc/κ t cs _ Cs)
       `(,(.id-name t) ,@(reverse (show-Vs σ Cs)) ,acc ,@(map (curry show-e σ) cs))]
      [(.rt/κ _ _ _) `(rt ,acc)]
      [(.blr/κ _ _ _) `(blr ,acc)]
      [(.recchk/κ _ _) `(recchk ,acc)]
      [(.μ/κ _ _ _) `(μ/κ ,acc)])))

(: print-ς : .ς → Void)
(define (print-ς ς) (printf (format-ς ς)))

(: format-ς : .ς → String)
(define (format-ς ς)
  (match-define (.ς E σ k) ς)
  (parameterize ([abstract-V? #f])
    (cond [(.E? E)
           (format "---- E: ~a~n     σ: ~a~n~n"
                   (show-ek σ k `(⦃,(show-E σ E)⦄))
                   (show-σ σ))]
          [else
           (format "---- K: ~a~n     σ: ~a~n~n"
                   (show-ek σ k `(⟦,(show-κ σ (car E))⟧))
                   (show-σ σ))])))
|#
