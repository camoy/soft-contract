#lang typed/racket/base

(provide mon@)

(require racket/set
         racket/list
         racket/match
         typed/racket/unit
         bnf
         set-extras
         unreachable
         (only-in "../utils/map.rkt" m⊔)
         "../ast/signatures.rkt"
         "../runtime/signatures.rkt"
         "../execution/signatures.rkt"
         "../signatures.rkt"
         "signatures.rkt"
         )

(⟦C⟧ . ≜ . (Σ Ctx V^ → (Values R (℘ Err))))

(define-unit mon@
  (import static-info^
          cache^ val^ sto^ pretty-print^
          exec^ app^ gc^
          prover^)
  (export mon^)

  (define -FF {set -ff})
  (define γ-mon (γ:lex (gensym 'mon_)))

  (: mon : Σ Ctx V^ V^ → (Values R (℘ Err)))
  (define (mon Σ ctx C^ V^)
    (define args:root (V^-root V^))
    (fold-ans (λ ([C : V])
                (define root (∪ (V-root C) args:root))
                (define Σ* (gc root Σ))
                (ref-$! ($:Key:Mon Σ* ctx C V^)
                        (λ () (with-gc root (λ () ((mon₁ C) Σ* ctx V^))))))
              (unpack C^ Σ)))

  (: mon* : Σ Ctx W W → (Values R (℘ Err)))
  (define (mon* Σ₀ ctx Cs Vs)
    (if (= (length Cs) (length Vs))
        (let loop ([ΔΣ : ΔΣ ⊥ΔΣ] [Σ : Σ Σ₀] [rev-As : W '()] [es : (℘ Err) ∅] [Cs : W Cs] [Vs : W Vs])
          (match* (Cs Vs)
            [((cons C₁ Cs*) (cons V₁ Vs*))
             (define-values (r₁ es₁) (mon Σ ctx C₁ V₁))
             (match (collapse-R r₁)
               [(cons (app collapse-W^ (app car A₁)) ΔΣ₁)
                (loop (⧺ ΔΣ ΔΣ₁) (⧺ Σ ΔΣ₁) (cons A₁ rev-As) (∪ es es₁) Cs* Vs*)]
               [#f (values ⊥R (∪ es es₁))])]
            [('() '())
             (values (R-of (reverse rev-As) ΔΣ) es)]))
        (match-let ([(Ctx l+ _ ℓₒ ℓ) ctx])
          (err (blm l+ ℓ ℓₒ Cs Vs)))))

  (: mon₁ : V → ⟦C⟧)
  (define (mon₁ C)
    (cond [(Fn/C? C) (mon-Fn/C C)]
          [(St/C? C) (mon-St/C C)]
          [(X/C? C) (mon-X/C (X/C-_0 C))]
          [(And/C? C) (mon-And/C C)]
          [(Or/C? C) (mon-Or/C C)]
          [(Not/C? C) (mon-Not/C C)]
          [(One-Of/C? C) (mon-One-Of/C C)]
          [(Vectof/C? C) (mon-Vectof/C C)]
          [(Vect/C? C) (mon-Vect/C C)]
          [(Hash/C? C) (mon-Hash/C C)]
          [(Set/C? C) (mon-Set/C C)]
          [(Seal/C? C) (mon-Seal/C C)]
          [else (mon-Flat/C C)]))

  (: mon-Fn/C : Fn/C → ⟦C⟧)
  (define ((mon-Fn/C C) Σ ctx Vs)
    (match-define (Ctx l+ _ ℓₒ ℓ) ctx)
    (with-split-Σ Σ 'procedure? (list Vs)
      (λ (W ΔΣ₁)
        (define arity-check (P:arity-includes (guard-arity C)))
        (with-split-Σ Σ arity-check W
          (match-lambda**
           [((list V*) ΔΣ₂)
            (define αᵥ (α:dyn (β:fn ctx) H₀))
            (just (Guarded ctx C αᵥ) (alloc αᵥ V*))])
          (λ (W _) (err (blm l+ ℓₒ ℓ (list {set arity-check}) W)))))
      (λ (W _) (err (blm l+ ℓₒ ℓ (list {set 'procedure?}) W)))))

  (: mon-St/C : St/C → ⟦C⟧)
  (define ((mon-St/C C) Σ₀ ctx Vs)
    (match-define (Ctx l+ _ ℓₒ ℓ) ctx)
    (match-define (St/C 𝒾 αs ℓₕ) C)

    (: mon-St/C-fields : Σ V^ → (Values R (℘ Err)))
    (define (mon-St/C-fields Σ V)
      (let go ([i : Index 0] [αs : (Listof α) αs] [Vs-rev : W '()] [ΔΣ : ΔΣ ⊥ΔΣ])
        (match αs
          ['() (just (reverse Vs-rev) ΔΣ)]
          [(cons αᵢ αs*)
           (with-collapsing/R [(ΔΣ₀ Ws) (app (⧺ Σ ΔΣ) ℓ {set (-st-ac 𝒾 i)} (list V))]
             (with-collapsing/R [(ΔΣ₁ Ws*) (mon (⧺ Σ ΔΣ ΔΣ₀) ctx (unpack αᵢ Σ) (car (collapse-W^ Ws)))]
               (go (assert (+ 1 i) index?)
                   αs*
                   (cons (car (collapse-W^ Ws*)) Vs-rev)
                   (⧺ ΔΣ ΔΣ₀ ΔΣ₁))))])))

    (with-split-Σ Σ₀ (-st-p 𝒾) (list Vs)
      (λ (W* ΔΣ)
        (with-collapsing/R [(ΔΣ* Ws) (mon-St/C-fields (⧺ Σ₀ ΔΣ) (car W*))]
          (define-values (αs ΔΣ**) (alloc-each (collapse-W^ Ws) (λ (i) (β:fld 𝒾 ℓₕ i))))
          (define V* {set (St 𝒾 αs ∅)})
          (if (struct-all-immutable? 𝒾)
              (just V* (⧺ ΔΣ ΔΣ* ΔΣ**))
              (let ([α (α:dyn (β:st 𝒾 ctx) H₀)])
                (just (Guarded ctx C α) (⧺ ΔΣ ΔΣ* ΔΣ** (alloc α V*)))))))
      (λ (W* _) (err (blm l+ ℓ ℓₒ (list {set C}) W*)))))

  (: mon-X/C : α → ⟦C⟧)
  ;; Need explicit contract reference to explicitly hint execution of loop
  (define ((mon-X/C α) Σ ctx V^) (mon Σ ctx (unpack α Σ) (unpack V^ Σ)))

  (: mon-And/C : And/C → ⟦C⟧)
  (define ((mon-And/C C) Σ ctx V^)
    (match-define (And/C α₁ α₂ ℓ) C)
    (with-collapsing/R [(ΔΣ₁ Ws₁) (mon Σ ctx (unpack α₁ Σ) V^)]
      (match-define (list V^*) (collapse-W^ Ws₁))
      (with-pre ΔΣ₁ (mon (⧺ Σ ΔΣ₁) ctx (unpack α₂ Σ) V^*))))

  (: mon-Or/C : Or/C → ⟦C⟧)
  (define ((mon-Or/C C) Σ ctx V) 
    (: chk : V^ V^ → (Values R (℘ Err)))
    (define (chk C-fo C-ho)
      (with-each-path [(ΔΣ₁ Ws₁) (fc Σ (Ctx-origin ctx) C-fo V)]
        (for/fold ([r : R ⊥R] [es : (℘ Err) ∅]) ([W₁ (in-set Ws₁)])
          (match W₁
            [(list _) (values (m⊔ r (R-of W₁ ΔΣ₁)) es)]
            [(list V* _) (define-values (r₂ es₂) (mon (⧺ Σ ΔΣ₁) ctx C-ho V*))
                         (values (m⊔ r (ΔΣ⧺R ΔΣ₁ r₂)) (∪ es es₂))]))))

    (match-define (Or/C α₁ α₂ _) C)
    (define C₁ (unpack α₁ Σ))
    (define C₂ (unpack α₂ Σ))
    (cond [(C^-flat? C₁ Σ) (chk C₁ C₂)]
          [(C^-flat? C₂ Σ) (chk C₂ C₁)]
          [else (error 'or/c "No more than 1 higher-order disjunct for now")]))

  (: mon-Not/C : Not/C → ⟦C⟧)
  (define ((mon-Not/C C) Σ ctx V)
    (match-define (Not/C α _) C)
    (match-define (Ctx l+ _ ℓₒ ℓ) ctx)
    (with-each-path [(ΔΣ Ws) (fc Σ ℓₒ (unpack α Σ) V)]
      (for*/fold ([r : R ⊥R] [es : (℘ Err) ∅]) ([W (in-set Ws)])
        (match W
          [(list Vs* _) (values (m⊔ r (R-of Vs* ΔΣ)) es)]
          [(list _) (values r (∪ es (blm l+ ℓ ℓₒ (list {set C}) (list V))))]))))

  (: mon-One-Of/C : One-Of/C → ⟦C⟧)
  (define ((mon-One-Of/C C) Σ ctx Vs)
    (match-define (Ctx l+ _ ℓₒ ℓ) ctx)
    (with-split-Σ Σ C (list Vs)
      (λ (W ΔΣ) (just W ΔΣ))
      (λ (W ΔΣ) (err (blm l+ ℓ ℓₒ (list {set C}) W)))))

  (: mon-Vectof/C : Vectof/C → ⟦C⟧)
  (define ((mon-Vectof/C C) Σ ctx Vs)
    (match-define (Ctx l+ _ ℓₒ ℓ) ctx)
    (with-split-Σ Σ 'vector? (list Vs)
      (λ (W* ΔΣ₀)
        (match-define (Vectof/C αₕ _) C)
        (define N (-● {set 'exact-nonnegative-integer?}))
        (define Σ₀ (⧺ Σ ΔΣ₀))
        (with-collapsing/R [(ΔΣ₁ Wₑs) (app Σ₀ ℓ {set 'vector-ref} (list (car W*) {set N}))]
          (with-collapsing/R [(ΔΣ₂ Wₑs*) (mon (⧺ Σ₀ ΔΣ₁) ctx (unpack αₕ Σ) (car (collapse-W^ Wₑs)))]
            (define Vₑ (car (collapse-W^ Wₑs*)))
            (define αₑ (α:dyn (β:vct ℓ) H₀))
            (define αᵥ (α:dyn (β:unvct ctx) H₀))
            (just (Guarded ctx C αᵥ)
                  (⧺ ΔΣ₀ ΔΣ₁ ΔΣ₂ (alloc αₑ Vₑ) (alloc αᵥ {set (Vect-Of αₑ {set N})}))))))
      (λ (W* _) (err (blm l+ ℓₒ ℓ (list {set C}) W*)))))

  (: mon-Vect/C : Vect/C → ⟦C⟧)
  (define ((mon-Vect/C C) Σ ctx Vs)
    (match-define (Ctx l+ _ ℓₒ ℓ) ctx)
    (match-define (Vect/C αs _) C)
    (define n (length αs))
    (define (@ [α : α]) (unpack α Σ))

    (define (blame [V : V]) (blm l+ ℓₒ ℓ (list {set C}) (list {set V})))

    (: check-elems+wrap : W → (Values R (℘ Err)))
    (define (check-elems+wrap W)
      (with-collapsing/R [(ΔΣ Ws) (mon* Σ ctx (map @ αs) W)]
        (define W* (collapse-W^ Ws))
        (define αᵥ (α:dyn (β:unvct ctx) H₀))
        (define-values (αs* ΔΣ*) (alloc-each W* (λ (i) (β:idx ℓ i))))
        (just (Guarded ctx C αᵥ) (⧺ ΔΣ ΔΣ* (alloc αᵥ {set (Vect αs*)})))))
    
    ((inst fold-ans V)
     (match-lambda
       [(Vect αs*)
        #:when (= (length αs*) n)
        (check-elems+wrap (map @ αs*))]
       [(Vect-Of αᵥ Vₙ)
        (check-elems+wrap (make-list n (@ αᵥ)))]
       [(and V (? Guarded?))
        (define-values (args-rev ΔΣ₀ es₀)
          (for/fold ([args-rev : W '()] [ΔΣ : (Option ΔΣ) ⊥ΔΣ] [es : (℘ Err) ∅])
                    ([i (in-range n)] #:when ΔΣ)
            (define-values (rᵢ esᵢ) (app Σ ℓₒ {set 'vector-ref} (list {set V} {set (-b i)})))
            (match (collapse-R rᵢ)
              [(cons Wsᵢ ΔΣᵢ) (values (cons (car (collapse-W^ Wsᵢ)) args-rev)
                                      (⧺ (assert ΔΣ) ΔΣᵢ)
                                      (∪ es esᵢ))]
              [#f (values '() #f (∪ es esᵢ))])))
        (if ΔΣ₀
            (let-values ([(r* es*) (check-elems+wrap (reverse args-rev))])
              (values (ΔΣ⧺R ΔΣ₀ r*) (∪ es₀ es*)))
            (values ⊥R es₀))]
       [(and V (-● Ps))
        (if (∋ Ps 'vector?)
            (check-elems+wrap (make-list n {set (-● ∅)}))
            (err (blame V)))]
       [V (err (blame V))])
     Vs))

  (: mon-Hash/C : Hash/C → ⟦C⟧)
  (define ((mon-Hash/C C) Σ ctx V^)
    ???)

  (: mon-Set/C : Set/C → ⟦C⟧)
  (define ((mon-Set/C C) Σ ctx V^)
    ???)

  (: mon-Seal/C : Seal/C → ⟦C⟧)
  (define ((mon-Seal/C C) Σ ctx V^)
    ???)

  (: mon-Flat/C : V → ⟦C⟧)
  (define ((mon-Flat/C C) Σ ctx Vs)
    (match-define (Ctx l+ _ ℓₒ ℓ) ctx)
    (define (blame) (blm l+ ℓ ℓₒ (list {set C}) (list Vs)))
    (case (sat Σ C Vs)
      [(✓) (just Vs)]
      [(✗) (err (blame))]
      [else
       (with-each-path [(ΔΣ Ws) (fc Σ ℓₒ {set C} Vs)]
         (for*/fold ([r : R ⊥R] [es : (℘ Err) ∅]) ([W (in-set Ws)])
           (match W
             [(list _) (values (m⊔ r (R-of W ΔΣ)) es)]
             [(list Vs* _) (values r (∪ es (blame)))])))]))

  ;; Can't get away with not having specialized flat-check procedure.
  ;; There's no straightforward way to fully refine a value by contract `c`
  ;; after applying `c` as a procedure (tricky when `c` is recursive and effectful)
  ;; Convention: `fc` returns:
  ;; - `[refine(v, c)   ]` if `v`          satisfies `c`
  ;; - `[refine(v,¬c),#f]` if `v` does not satisfies `c`,
  (: fc : Σ ℓ V^ V^ → (Values R (℘ Err)))
  (define (fc Σ₀ ℓ Cs Vs)
    (define Vs:root (V^-root Vs))
    ((inst fold-ans V)
     (λ (C)
       (define root (∪ (V-root C) Vs:root))
       (define Σ₀* (gc root Σ₀))
       (ref-$! ($:Key:Fc Σ₀* ℓ C Vs)
               (λ () (with-gc root (λ () (fc₁ Σ₀* ℓ C Vs))))))
     Cs))

  (: fc₁ : Σ ℓ V V^ → (Values R (℘ Err)))
  (define (fc₁ Σ₀ ℓ C Vs)
    (match C
      [(And/C α₁ α₂ _)
       (with-collapsing/R [(ΔΣ₁ Ws₁) (fc Σ₀ ℓ (unpack α₁ Σ₀) Vs)]
         (for/fold ([r : R ⊥R] [es : (℘ Err) ∅]) ([W₁ (in-set Ws₁)])
           (match W₁
             [(list Vs*)
              (define-values (r₂ es₂) (fc (⧺ Σ₀ ΔΣ₁) ℓ (unpack α₂ Σ₀) Vs*))
              (values (m⊔ r (ΔΣ⧺R ΔΣ₁ r₂)) (∪ es es₂))]
             [(list _ _) (values (m⊔ r (R-of W₁ ΔΣ₁)) es)])))]
      [(Or/C α₁ α₂ _)
       (with-collapsing/R [(ΔΣ₁ Ws₁) (fc Σ₀ ℓ (unpack α₁ Σ₀) Vs)]
         (for/fold ([r : R ⊥R] [es : (℘ Err) ∅]) ([W₁ (in-set Ws₁)])
           (match W₁
             [(list _) (values (m⊔ r (R-of W₁ ΔΣ₁)) es)]
             [(list Vs* _)
              (define-values (r₂ es₂) (fc (⧺ Σ₀ ΔΣ₁) ℓ (unpack α₂ Σ₀) Vs*))
              (values (m⊔ r (ΔΣ⧺R ΔΣ₁ r₂)) (∪ es es₂))])))]
      [(Not/C α _)
       (with-collapsing/R [(ΔΣ₁ Ws₁) (fc Σ₀ ℓ (unpack α Σ₀) Vs)]
         (for/fold ([r : R ⊥R] [es : (℘ Err) ∅]) ([W₁ (in-set Ws₁)])
           (values (m⊔ r (R-of (match W₁
                                 [(list Vs*) (list Vs* -FF)]
                                 [(list Vs* _) (list Vs*)])
                               ΔΣ₁))
                   es)))]
      [(One-Of/C bs)
       (with-split-Σ Σ₀ (One-Of/C bs) (list Vs)
         just
         (λ (W ΔΣ) (just (list (car W) -FF) ΔΣ)))]
      [(St/C 𝒾 αs _)
       (with-split-Σ Σ₀ (-st-p 𝒾) (list Vs)
         (λ (W* ΔΣ*)
           (define n (count-struct-fields 𝒾))
           (let go ([Σ : Σ Σ₀] [αs : (Listof α) αs] [i : Index 0] [ΔΣ : ΔΣ ΔΣ*] [rev-W : W '()])
             (match αs
               ['()
                (define-values (αs* ΔΣ*) (alloc-each (reverse rev-W) (λ (i) (β:fld 𝒾 ℓ i))))
                (just (St 𝒾 αs* ∅) (⧺ ΔΣ ΔΣ*))]
               [(cons αᵢ αs*)
                (with-collapsing/R [(ΔΣ:a Ws:a) (app Σ ℓ {set (-st-ac 𝒾 i)} W*)]
                  (with-each-path [(ΔΣᵢ Wsᵢ) (fc (⧺ Σ ΔΣ:a) ℓ (unpack αᵢ Σ) (car (collapse-W^ Ws:a)))]
                    (for*/fold ([r : R ⊥R] [es : (℘ Err) ∅]) ([Wᵢ (in-set Wsᵢ)])
                      (match Wᵢ
                        [(list Vᵢ)
                         (define-values (r* es*) (go (⧺ Σ ΔΣ:a ΔΣᵢ)
                                                     αs* (assert (+ 1 i) index?)
                                                     (⧺ ΔΣ ΔΣ:a ΔΣᵢ) (cons Vᵢ rev-W)))
                         (values (m⊔ r r*) (∪ es es*))]
                        [(list Vᵢ _)
                         (define fields (append (reverse rev-W) (make-list (- n i 1) {set (-● ∅)})))
                         (define-values (αs* ΔΣ*) (alloc-each fields (λ (i) (β:fld 𝒾 ℓ i))))
                         (values (m⊔ r (R-of (list {set (St 𝒾 αs* ∅)} -FF) (⧺ ΔΣ:a ΔΣᵢ ΔΣ*))) es)]))))])))
         (λ (W ΔΣ) (just (list (car W) -FF) ΔΣ)))]
      [(X/C α) (fc Σ₀ ℓ (unpack α Σ₀) (unpack Vs Σ₀))]
      [(? -b? b)
       (with-split-Σ Σ₀ 'equal? (list {set b} Vs)
         (λ (_ ΔΣ) (just b ΔΣ))
         (λ (W ΔΣ) (just (list (car W) -FF) ΔΣ)))]
      [_
       (define ΔΣₓ (alloc γ-mon Vs))
       (with-each-path [(ΔΣ Ws) (app (⧺ Σ₀ ΔΣₓ) ℓ {set C} (list {set γ-mon}))]
         (define Σ₁ (⧺ Σ₀ ΔΣₓ ΔΣ))
         (define Vs* (unpack γ-mon Σ₁))
         (with-split-Σ Σ₁ 'values (collapse-W^ Ws)
           (λ _ (just Vs* ΔΣ))
           (λ _ (just (list Vs* -FF) ΔΣ))))]))
  )
