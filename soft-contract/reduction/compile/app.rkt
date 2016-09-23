#lang typed/racket/base

(provide app mon flat-chk
         ap∷ let∷ if∷ and∷ or∷ bgn∷)

(require "../../utils/main.rkt"
         "../../ast/main.rkt"
         "../../runtime/main.rkt"
         "../../proof-relation/main.rkt"
         "../delta.rkt"
         "utils.rkt"
         "base.rkt"
         racket/set
         racket/match)

(: app : -l -ℓ -W¹ (Listof -W¹) -Γ -𝒞 -Σ -⟦k⟧! → (℘ -ς))
(define (app l ℓ Wₕ Wₓs Γ 𝒞 Σ ⟦k⟧)
  (match-define (-Σ σ σₖ M) Σ)
  (match-define (-W¹ Vₕ sₕ) Wₕ)
  (define-values (Vₓs sₓs) (unzip-by -W¹-V -W¹-s Wₓs))
  (define sₐ
    (let ([sₕ* (match Vₕ
                 [(? -o? o) o]
                 [(-Ar _ (-α.def (-𝒾 o 'Λ)) _) o]
                 [(-Ar _ (-α.wrp (-𝒾 o 'Λ)) _) o]
                 [_ sₕ])])
      (apply -?@ sₕ* sₓs)))

  (: blm-arity : Arity Natural → -blm)
  (define (blm-arity required provided)
    ;; HACK for error message. Probably no need to fix
    (define msg : Symbol
      (cond
        [sₕ (format-symbol "~a requires ~a arguments" (format "~a" (show-e sₕ)) required)]
        [else (format-symbol "require ~a arguments" required)]))
    (-blm l 'Λ (list msg) Vₓs))

  (define-syntax-rule (with-guarded-arity a* e ...)
    (let ([n (length Wₓs)]
          [a a*])
      (cond
        [(arity-includes? a n) e ...]
        [else (⟦k⟧ (blm-arity a n) Γ 𝒞 Σ)])))

  (define (app-st-p [s : -struct-info])
    (define A
      (case (MΓ⊢oW M Γ (-st-p s) (car Wₓs))
        [(✓) -True/Vs]
        [(✗) -False/Vs]
        [(?) -Bool/Vs]))
    (⟦k⟧ (-W A sₐ) Γ 𝒞 Σ))

  (define (app-st-mk [s : -struct-info])
    (define 𝒾 (-struct-info-id s))
    (define αs : (Listof -α.fld)
      (for/list ([i : Natural (-struct-info-arity s)])
        (-α.fld 𝒾 ℓ 𝒞 i)))
    (for ([α αs] [Vₓ Vₓs])
      (σ⊔! σ α Vₓ #t))
    (define V (-St s αs))
    (⟦k⟧ (-W (list V) sₐ) Γ 𝒞 Σ))

  ;; Apply accessor
  (define (app-st-ac [s : -struct-info] [i : Natural])
    (define n (-struct-info-arity s))
    (match-define (list (and Wₓ (-W¹ Vₓ sₓ))) Wₓs)
    (define ac (-st-ac s i))
    (define p  (-st-p s))
    (define (blm) (-blm l (show-o ac) (list p) (list Vₓ)))

    (match Vₓ
      [(-St (== s) αs)
       (define α (list-ref αs i))
       (define-values (Vs _) (σ@ σ α))
       (for/union : (℘ -ς) ([V Vs])
         (⟦k⟧ (-W (list V) sₐ) Γ 𝒞 Σ))]
      [(-St* (== s) αs α l³)
       (match-define (-l³ _ _ lₒ) l³)
       (define Ac (-W¹ ac ac))
       (cond
         ;; field is wrapped
         [(list-ref αs i) =>
          (λ ([αᵢ : -α])
            (define (Cᵢs _) (σ@ σ αᵢ))
            (error 'app-st-ac "TODO: wrapped mutable field"))]
         ;; field is unwrapped because it's immutable
         [else
          (define-values (Vₓ*s _) (σ@ σ α))
          (for/union : (℘ -ς) ([Vₓ* Vₓ*s]) ;; TODO: could this loop forever due to cycle?
            (app lₒ ℓ Ac (list (-W¹ Vₓ* sₓ)) Γ 𝒞 Σ ⟦k⟧))])]
      [(-● _)
       (with-Γ+/- ([(Γₒₖ Γₑᵣ) (Γ+/-W∋Ws M Γ (-W¹ p p) Wₓ)])
         #:true  (⟦k⟧ (-W -●/Vs sₐ) Γₒₖ 𝒞 Σ)
         #:false (⟦k⟧ (blm) Γₑᵣ 𝒞 Σ))]
      [_ (⟦k⟧ (blm) Γ 𝒞 Σ)]))

  (define (app-st-mut [s : -struct-info] [i : Natural])
    (match-define (list Wₛ Wᵥ) Wₓs)
    (match-define (-W¹ Vₛ sₛ) Wₛ)
    (match-define (-W¹ Vᵥ _ ) Wᵥ)
    (define mut (-st-mut s i))
    (define p (-st-p s))
    (define (blm) (-blm l (show-o mut) (list p) (list Vₛ)))
    
    (match Vₛ
      [(-St (== s) αs)
       (define α (list-ref αs i))
       (σ⊔! σ α Vᵥ #f)
       (⟦k⟧ -Void/W Γ 𝒞 Σ)]
      [(-St* (== s) γs α l³)
       (match-define (-l³ l+ l- lo) l³)
       (define l³* (-l³ l- l+ lo))
       (match-define (? -α? γ) (list-ref γs i))
       (define c (and (-e? γ) γ))
       (define Mut (-W¹ mut mut))
       (for*/union : (℘ -ς) ([C (σ@ᵥ σ γ)] [Vₛ* (σ@ᵥ σ α)])
         (define W-c (-W¹ C c))
         (define Wₛ* (-W¹ Vₛ* sₛ))
         (mon l³* ℓ W-c Wᵥ Γ 𝒞 Σ
              (ap∷ (list Wₛ Mut) '() ⊥ρ lo ℓ ⟦k⟧)))]
      [(-● _)
       (define ⟦ok⟧
         (let ([Wₕᵥ (-W¹ (σ@¹ σ (-α.def havoc-𝒾)) havoc-𝒾)])
           (define ⟦hv⟧ (mk-app-⟦e⟧ havoc-path ℓ (mk-rt-⟦e⟧ Wₕᵥ) (list (mk-rt-⟦e⟧ Wᵥ))))
           (mk-app-⟦e⟧ havoc-path ℓ (mk-rt-⟦e⟧ (-W¹ 'void 'void)) (list ⟦hv⟧))))
       (define ⟦er⟧ (mk-rt-⟦e⟧ (blm)))
       (app 'Λ ℓ (-W¹ p p) (list Wₛ) Γ 𝒞 Σ (if∷ l ⟦ok⟧ ⟦er⟧ ⊥ρ ⟦k⟧))]
      [_ (⟦k⟧ (blm) Γ 𝒞 Σ)]))

  (define (app-unsafe-struct-ref)
    (match-define (list Wᵥ Wᵢ) Wₓs)
    (match-define (-W¹ Vᵥ sᵥ) Wᵥ)
    (match-define (-W¹ Vᵢ sᵢ) Wᵢ)
    (match Vᵥ
      [(-St (-struct-info _ n _) αs)
       (for*/union : (℘ -ς) ([(α i) (in-indexed αs)]
                             #:when (exact-nonnegative-integer? i) ; hack for TR
                             #:when (plausible-index? M Γ Wᵢ i)
                             [Γ* (in-value (Γ+ Γ (-?@ '= sᵢ (-b i))))]
                             [V (σ@ᵥ σ α)])
         (⟦k⟧ (-W (list V) sₐ) Γ* 𝒞 Σ))]
      [(-St* (-struct-info _ n _) γs α l³)
       (match-define (-l³ l+ l- lo) l³)
       (for*/union : (℘ -ς) ([(γ i) (in-indexed γs)]
                            #:when (exact-nonnegative-integer? i)
                            #:when (plausible-index? M Γ Wᵢ i)
                            [Γ* (in-value (Γ+ Γ (-?@ '= sᵢ (-b i))))]
                            [c (in-value (and (-e? γ) γ))]
                            [V (σ@ᵥ σ α)]
                            [C (if γ (σ@ᵥ σ γ) {set #f})])
          (cond
            [C
             (app lo ℓ -unsafe-struct-ref/W (list (-W¹ V sᵥ)) Γ* 𝒞 Σ
                  (mon.c∷ l³ ℓ (-W¹ C c) ⟦k⟧))]
            [else
             (app lo ℓ -unsafe-struct-ref/W (list (-W¹ V sᵥ)) Γ* 𝒞 Σ ⟦k⟧)]))]
      [_
       (⟦k⟧ (-W -●/Vs sₐ) Γ 𝒞 Σ)]))

  (define (app-unsafe-struct-set!)
    (error 'app-unsafe-struct-set! "TODO"))

  (define (app-vector-ref)
    (match-define (list Wᵥ Wᵢ) Wₓs)
    (match-define (-W¹ Vᵥ sᵥ) Wᵥ)
    (match-define (-W¹ Vᵢ sᵢ) Wᵢ)
    (match Vᵥ
      [(-Vector αs)
       (for*/union : (℘ -ς) ([(α i) (in-indexed αs)]
                            #:when (exact-nonnegative-integer? i) ; hack for TR
                            #:when (plausible-index? M Γ Wᵢ i)
                            [Γ* (in-value (Γ+ Γ (-?@ '= sᵢ (-b i))))]
                            [V (σ@ᵥ σ α)])
          (⟦k⟧ (-W (list V) sₐ) Γ* 𝒞 Σ))]
      [(-Vector/hetero αs l³)
       (match-define (-l³ _ _ lo) l³)
       (for*/union : (℘ -ς) ([(α i) (in-indexed αs)]
                            #:when (exact-nonnegative-integer? i) ; hack for TR
                            #:when (plausible-index? M Γ Wᵢ i)
                            [Γ* (in-value (Γ+ Γ (-?@ '= sᵢ (-b i))))]
                            [c (in-value (and (-e? α) α))]
                            [C (σ@ᵥ σ α)])
          (mon l³ ℓ (-W¹ C c) (-W¹ -●/V sₐ) Γ* 𝒞 Σ ⟦k⟧))]
      [(-Vector/homo α l³)
       (match-define (-l³ _ _ lo) l³)
       (define c (and (-e? α) α))
       (for/union : (℘ -ς) ([C (σ@ᵥ σ α)])
         (mon l³ ℓ (-W¹ C c) (-W¹ -●/V sₐ) Γ 𝒞 Σ ⟦k⟧))]
      [_
       (⟦k⟧ (-W -●/Vs sₐ) Γ 𝒞 Σ)]))

  (define (app-vector-set!)
    (match-define (list Wᵥ Wᵢ Wᵤ) Wₓs)
    (match-define (-W¹ Vᵥ sᵥ) Wᵥ)
    (match-define (-W¹ Vᵢ sᵢ) Wᵢ)
    (match-define (-W¹ Vᵤ sᵤ) Wᵤ)
    (define Wₕᵥ (-W¹ (σ@¹ σ (-α.def havoc-𝒾)) havoc-𝒾))
    (match Vᵥ
      [(-Vector αs)
       (for*/union : (℘ -ς) ([(α i) (in-indexed αs)]
                            #:when (exact-nonnegative-integer? i) ; hack for TR
                            #:when (plausible-index? M Γ Wᵢ i))
         (define Γ* (Γ+ Γ (-?@ '= sᵢ (-b i))))
         (σ⊔! σ α Vᵤ #f)
         (⟦k⟧ -Void/W Γ* 𝒞 Σ))]
      [(-Vector/hetero αs l³)
       (match-define (-l³ l+ l- lo) l³)
       (define l³* (-l³ l- l+ lo))
       (for*/union : (℘ -ς) ([(α i) (in-indexed αs)]
                            #:when (exact-nonnegative-integer? i) ; hack for TR
                            #:when (plausible-index? M Γ Wᵢ i)
                            [Γ* (in-value (Γ+ Γ (-?@ '= sᵢ (-b i))))]
                            [c (in-value (and (-e? α) α))]
                            [C (σ@ᵥ σ α)])
         (define W-c (-W¹ C c))
         (define ⟦hv⟧
           (let ([⟦chk⟧ (mk-mon-⟦e⟧ l³* ℓ (mk-rt-⟦e⟧ W-c) (mk-rt-⟦e⟧ Wᵤ))])
             (mk-app-⟦e⟧ havoc-path ℓ (mk-rt-⟦e⟧ Wₕᵥ) (list ⟦chk⟧))))
         ((mk-app-⟦e⟧ lo ℓ (mk-rt-⟦e⟧ (-W¹ 'void 'void)) (list ⟦hv⟧)) ⊥ρ Γ* 𝒞 Σ ⟦k⟧))]
      [(-Vector/homo α l³)
       (define c (and (-e? α) α))
       (define l³* (swap-parties l³))
       (for/union : (℘ -ς) ([C (σ@ᵥ σ α)])
         (define W-c (-W¹ C c))
         (define ⟦hv⟧
           (let ([⟦chk⟧ (mk-mon-⟦e⟧ l³* ℓ (mk-rt-⟦e⟧ W-c) (mk-rt-⟦e⟧ Wᵤ))])
             (mk-app-⟦e⟧ havoc-path ℓ (mk-rt-⟦e⟧ Wₕᵥ) (list ⟦chk⟧))))
         ((mk-app-⟦e⟧ havoc-path ℓ (mk-rt-⟦e⟧ (-W¹ 'void 'void)) (list ⟦hv⟧)) ⊥ρ Γ 𝒞 Σ ⟦k⟧))]
      [_
       (∪ (app havoc-path ℓ Wₕᵥ (list Wᵤ) Γ 𝒞 Σ ⟦k⟧)
          (⟦k⟧ -Void/W Γ 𝒞 Σ))]))

  (define (app-contract-first-order-passes?)
    (error 'app-contract-first-order-passes? "TODO"))

  (define (app-δ [o : Symbol])
    (define ?Vs (δ! 𝒞 ℓ M σ Γ o Wₓs))
    (cond [?Vs (⟦k⟧ (-W ?Vs sₐ) Γ 𝒞 Σ)]
          [else ∅]))

  (define (app-clo [xs : -formals] [⟦e⟧ : -⟦e⟧!] [ρₕ : -ρ] [Γₕ : -Γ])
    (define 𝒞* (𝒞+ 𝒞 (cons ⟦e⟧ ℓ)))
    (cond
      [(list? xs)
       (define ρ* ; with side effects widening store
         (for/fold ([ρ : -ρ ρₕ]) ([x xs] [Vₓ Vₓs])
           (define α (-α.x x 𝒞*))
           (σ⊔! σ α Vₓ #t)
           (ρ+ ρ x α)))
       (define bnd
         (-binding sₕ
                   xs
                   (for/hasheq : (HashTable Var-Name -s) ([x xs] [sₓ sₓs] #:when sₓ)
                     (values x sₓ))))
       (define αₖ (-ℬ ⟦e⟧ ρ*))
       (define κ (-κ ⟦k⟧ Γ 𝒞 bnd))
       (vm⊔! σₖ αₖ κ)
       {set (-ς↑ αₖ Γₕ 𝒞*)}]
      [else (error 'app-clo "TODO: varargs: ~a" (show-V Vₕ))]))

  (define (app-And/C [W₁ : -W¹] [W₂ : -W¹]) : (℘ -ς)
    (define ⟦rhs⟧ (mk-app-⟦e⟧ l ℓ (mk-rt-⟦e⟧ W₂) (list (mk-rt-⟦e⟧ (car Wₓs)))))
    (app l ℓ W₁ Wₓs Γ 𝒞 Σ (and∷ l (list ⟦rhs⟧) ⊥ρ ⟦k⟧)))

  (define (app-Or/C [W₁ : -W¹] [W₂ : -W¹]) : (℘ -ς)
    (define ⟦rhs⟧ (mk-app-⟦e⟧ l ℓ (mk-rt-⟦e⟧ W₂) (list (mk-rt-⟦e⟧ (car Wₓs)))))
    (app l ℓ W₁ Wₓs Γ 𝒞 Σ (or∷ l (list ⟦rhs⟧) ⊥ρ ⟦k⟧)))
  
  (define (app-Not/C [Wᵤ : -W¹]) : (℘ -ς)
    (app l ℓ Wᵤ Wₓs Γ 𝒞 Σ (neg∷ l ⟦k⟧)))

  (define (app-St/C [s : -struct-info] [W-Cs : (Listof -W¹)]) : (℘ -ς)
    (match-define (list Wₓ) Wₓs)
    (match-define (-W¹ Vₓ _) Wₓ)
    (match Vₓ
      [(or (-St (== s) _) (-St* (== s) _ _ _))
       (define ⟦chk-field⟧s : (Listof -⟦e⟧!)
         (for/list ([(W-C i) (in-indexed W-Cs)]
                    #:when (exact-nonnegative-integer? i))
           (define Ac (let ([ac (-st-ac s i)]) (-W¹ ac ac)))
           (mk-app-⟦e⟧ l ℓ (mk-rt-⟦e⟧ W-C)
                       (list (mk-app-⟦e⟧ l ℓ (mk-rt-⟦e⟧ Ac) (list (mk-rt-⟦e⟧ Wₓ)))))))
       (define P (let ([p (-st-p s)]) (-W¹ p p)))
       (app l ℓ P (list Wₓ) Γ 𝒞 Σ (and∷ l ⟦chk-field⟧s ⊥ρ ⟦k⟧))]
      [_
       (⟦k⟧ -False/W Γ 𝒞 Σ)]))

  (define (app-Ar [C : -V] [Vᵤ : -V] [l³ : -l³]) : (℘ -ς)
    (match-define (-l³ l+ l- lo) l³)
    (define Wᵤ (-W¹ Vᵤ sₕ)) ; inner function
    (match-define (-=> αs β _) C)
    (define d (and (-e? β) β))
    (match-define (-Σ σ _ _) Σ)
    (match αs
      ['() ; no arg
       (for/union : (℘ -ς) ([D (σ@ᵥ σ β)])
         (app lo ℓ Wᵤ '() Γ 𝒞 Σ
              (mon.c∷ l³ ℓ (-W¹ D d) ⟦k⟧)))]
      [(cons α αs*)
       (define cs : (Listof -s) (for/list ([α αs]) (and (-e? α) α)))
       (define l³* (-l³ l- l+ lo))
       (for/union : (℘ -ς) ([Cs (σ@/list σ αs)])
          (match-define (cons ⟦mon-x⟧ ⟦mon-x⟧s)
            (for/list : (Listof -⟦e⟧!) ([C Cs] [c cs] [Wₓ Wₓs])
              (mk-mon-⟦e⟧ l³* ℓ (mk-rt-⟦e⟧ (-W¹ C c)) (mk-rt-⟦e⟧ Wₓ))))
          (for/union : (℘ -ς) ([D (σ@ᵥ σ β)])
             (⟦mon-x⟧ ⊥ρ Γ 𝒞 Σ
              (ap∷ (list Wᵤ) ⟦mon-x⟧s ⊥ρ lo ℓ
                   (mon.c∷ l³ ℓ (-W¹ D d) ⟦k⟧)))))]))

  (define (app-Indy [C : -V] [Vᵤ : -V] [l³ : -l³]) : (℘ -ς)
    (match-define (-l³ l+ l- lo) l³)
    (define l³* (-l³ l- l+ lo))
    (define Wᵤ (-W¹ Vᵤ sₕ)) ; inner function
    (match-define (-=>i αs γ _) C)
    (define cs : (Listof -s) (for/list ([α αs]) (and (-e? α) α)))
    (define mk-d (and (-λ? γ) γ))

    ;; FIXME tmp. copy n paste. Remove duplication
    (match mk-d
      [(-λ (? list? xs) d)
       (for/union : (℘ -ς) ([Mk-D (σ@ᵥ σ γ)])
         (match-define (-Clo _ ⟦d⟧ _ _) Mk-D)
         (for/union : (℘ -ς) ([Cs (σ@/list σ αs)])
            (define ⟦mon-x⟧s : (Listof -⟦e⟧!)
              (for/list ([C Cs] [c cs] [Wₓ Wₓs])
                (mk-mon-⟦e⟧ l³* ℓ (mk-rt-⟦e⟧ (-W¹ C c)) (mk-rt-⟦e⟧ Wₓ))))
            (define ⟦x⟧s : (Listof -⟦e⟧!) (for/list ([x xs]) (↓ₓ 'Λ x)))
            (match* (xs ⟦x⟧s ⟦mon-x⟧s)
              [('() '() '())
               (define ⟦ap⟧ (mk-app-⟦e⟧ lo ℓ (mk-rt-⟦e⟧ Wᵤ) '()))
               (define ⟦mon⟧ (mk-mon-⟦e⟧ l³ ℓ ⟦d⟧ ⟦ap⟧))
               (⟦mon⟧ ⊥ρ Γ 𝒞 Σ ⟦k⟧)]
              [((cons x xs*) (cons ⟦x⟧ ⟦x⟧s*) (cons ⟦mon-x⟧ ⟦mon-x⟧s*))
               (define ⟦app⟧ (mk-app-⟦e⟧ lo ℓ (mk-rt-⟦e⟧ Wᵤ) ⟦x⟧s))
               (define ⟦mon⟧ (mk-mon-⟦e⟧ l³ ℓ ⟦d⟧ ⟦app⟧))
               (⟦mon-x⟧ ⊥ρ Γ 𝒞 Σ
                (let∷ lo
                      (list x)
                      (for/list ([xᵢ xs*] [⟦mon⟧ᵢ ⟦mon-x⟧s*])
                        (cons (list xᵢ) ⟦mon⟧ᵢ))
                      '()
                      ⟦mon⟧
                      ⊥ρ
                      ⟦k⟧))])))]
      [_
       (for/union : (℘ -ς) ([Mk-D (σ@ᵥ σ γ)])
         (match-define (-Clo xs _ _ _) Mk-D)
         (define W-rng (-W¹ Mk-D mk-d))
         (match xs
           [(? list? xs)
            (define ⟦x⟧s : (Listof -⟦e⟧!) (for/list ([x xs]) (↓ₓ lo x)))
            (for/union : (℘ -ς) ([Cs (σ@/list σ αs)])
              (define ⟦mon-x⟧s : (Listof -⟦e⟧!)
                (for/list ([C Cs] [c cs] [Wₓ Wₓs])
                  (mk-mon-⟦e⟧ l³* ℓ (mk-rt-⟦e⟧ (-W¹ C c)) (mk-rt-⟦e⟧ Wₓ))))
              (match* (xs ⟦x⟧s ⟦mon-x⟧s)
                [('() '() '())
                 (define ⟦app⟧  (mk-app-⟦e⟧ lo ℓ (mk-rt-⟦e⟧ Wᵤ   ) '()))
                 (define ⟦mk-d⟧ (mk-app-⟦e⟧ lo ℓ (mk-rt-⟦e⟧ W-rng) '()))
                 (define ⟦mon⟧ (mk-mon-⟦e⟧ l³ ℓ ⟦mk-d⟧ ⟦app⟧))
                 (⟦mon⟧ ⊥ρ Γ 𝒞 Σ ⟦k⟧)]
                [((cons x xs*) (cons ⟦x⟧ ⟦x⟧s*) (cons ⟦mon-x⟧ ⟦mon-x⟧s*))
                 (define ⟦mon-y⟧
                   (let ([⟦mk-d⟧ (mk-app-⟦e⟧ lo ℓ (mk-rt-⟦e⟧ W-rng) ⟦x⟧s)]
                         [⟦app⟧  (mk-app-⟦e⟧ lo ℓ (mk-rt-⟦e⟧ Wᵤ   ) ⟦x⟧s)])
                     (mk-mon-⟦e⟧ l³ ℓ ⟦mk-d⟧ ⟦app⟧)))
                 (⟦mon-x⟧ ⊥ρ Γ 𝒞 Σ
                  (let∷ lo
                        (list x)
                        (for/list ([xᵢ xs*] [⟦mon⟧ᵢ ⟦mon-x⟧s*])
                          (cons (list xᵢ) ⟦mon⟧ᵢ))
                        '()
                        ⟦mon-y⟧
                        ⊥ρ
                         ⟦k⟧))]))]
           [(-varargs zs z)
            (error 'app-Indy "Apply variable arity arrow")]))]))

  (define (app-Case [C : -V] [Vᵤ : -V] [l³ : -l³]) : (℘ -ς)
    (error 'app-Case "TODO"))

  (define (app-opq) : (℘ -ς)
    (define Wₕᵥ
      (let-values ([(Vs _) (σ@ σ (-α.def havoc-𝒾))])
        (assert (= 1 (set-count Vs)))
        (-W¹ (set-first Vs) havoc-𝒾)))
    (for/fold ([ac : (℘ -ς) (⟦k⟧ (-W -●/Vs sₐ) Γ 𝒞 Σ)])
              ([Wₓ Wₓs])
      (app 'Λ ℓ Wₕᵥ (list Wₓ) Γ 𝒞 Σ ⟦k⟧)))
  
  (match Vₕ
    ;; Struct operators cannot be handled by `δ`, because structs can be arbitrarily wrapped
    ;; by proxies, and contract checking is arbitrarily deep
    ;; Also, there's no need to check for preconditions, because they should have been caught
    ;; by wrapping contracts
    [(-st-p  s) (app-st-p  s)]
    [(-st-mk s) (app-st-mk s)]
    [(-st-ac  s i) (with-guarded-arity 1 (app-st-ac  s i))]
    [(-st-mut s i) (with-guarded-arity 2 (app-st-mut s i))]
    ['contract-first-order-passes? (app-contract-first-order-passes?)]
    ['vector-ref (app-vector-ref)]
    ['vector-set! (app-vector-set!)]
    ['unsafe-struct-ref  (app-unsafe-struct-ref)]
    ['unsafe-struct-set! (app-unsafe-struct-set!)]

    ;; Regular stuff
    [(? symbol? o) (app-δ o)]
    [(-Clo xs ⟦e⟧ ρₕ Γₕ)
     (with-guarded-arity (formals-arity xs)
       (app-clo xs ⟦e⟧ ρₕ Γₕ))]
    [(-Case-Clo clauses ρ Γ)
     (define n (length Wₓs))
     (define clause
       (for/or : (Option (Pairof (Listof Var-Name) -⟦e⟧!)) ([clause clauses])
         (match-define (cons xs _) clause)
         (and (equal? n (length xs)) clause)))
     (cond
       [clause
        (match-define (cons xs ⟦e⟧) clause)
        (app-clo xs ⟦e⟧ ρ Γ)]
       [else
        (define a (assert (V-arity Vₕ)))
        (⟦k⟧ (blm-arity a n) Γ 𝒞 Σ)])]
    [(-Ar C α l³)
     (with-guarded-arity (guard-arity C)
       (cond
         [(-=>? C)  (for/union : (℘ -ς) ([Vᵤ (σ@ᵥ σ α)]) (app-Ar   C Vᵤ l³))]
         [(-=>i? C) (for/union : (℘ -ς) ([Vᵤ (σ@ᵥ σ α)]) (app-Indy C Vᵤ l³))]
         [else      (for/union : (℘ -ς) ([Vᵤ (σ@ᵥ σ α)]) (app-Case C Vᵤ l³))]))]
    [(-And/C #t α₁ α₂)
     (with-guarded-arity 1
       (define-values (c₁ c₂)
         (match-let ([(list s₁ s₂) (-app-split sₕ 'and/c 2)])
           (values (or s₁ (and (-e? α₁) α₁))
                   (or s₂ (and (-e? α₂) α₂)))))
       (for*/union : (℘ -ς) ([C₁ (σ@ᵥ σ α₁)] [C₂ (σ@ᵥ σ α₂)])
         (app-And/C (-W¹ C₁ c₁) (-W¹ C₂ c₂))))]
    [(-Or/C #t α₁ α₂)
     (with-guarded-arity 1
       (define-values (c₁ c₂)
         (match-let ([(list s₁ s₂) (-app-split sₕ 'or/c 2)])
           (values (or s₁ (and (-e? α₁) α₁))
                   (or s₂ (and (-e? α₂) α₂)))))
       (for*/union : (℘ -ς) ([C₁ (σ@ᵥ σ α₁)] [C₂ (σ@ᵥ σ α₂)])
         (app-Or/C (-W¹ C₁ c₁) (-W¹ C₂ c₂))))]
    [(-Not/C α)
     (with-guarded-arity 1
       (define c*
         (match-let ([(list s) (-app-split sₕ 'not/c 1)])
           (or s (and (-e? α) α))))
       (for/union : (℘ -ς) ([C* (σ@ᵥ σ α)])
         (app-Not/C (-W¹ C* c*))))]
    [(-St/C #t s αs)
     (with-guarded-arity 1
       (define cs : (Listof -s)
         (for/list ([s (-struct/c-split sₕ (-struct-info-arity s))]
                    [α αs])
           (or s (and (-e? α) α))))
       (for/union : (℘ -ς) ([Cs (σ@/list σ αs)])
         (app-St/C s (map -W¹ Cs cs))))]
    [(-● _)
     (case (MΓ⊢oW M Γ 'procedure? Wₕ)
       [(✓ ?) (app-opq)]
       [(✗) (⟦k⟧ (-blm l 'Λ (list 'procedure?) (list Vₕ)) Γ 𝒞 Σ)])]
    [_ (error 'app "TODO: ~a" (show-V Vₕ))]))

(: mon : -l³ -ℓ -W¹ -W¹ -Γ -𝒞 -Σ -⟦k⟧! → (℘ -ς))
(define (mon l³ ℓ W-C W-V Γ 𝒞 Σ ⟦k⟧)
  (match-define (-W¹ C c) W-C)
  (match-define (-W¹ V v) W-V)
  (match-define (-l³ l+ _ lo) l³)
  (case (MΓ⊢V∈C (-Σ-M Σ) Γ W-V W-C)
    [(✓) (⟦k⟧ (-W (list V) v) Γ 𝒞 Σ)]
    [(✗) (⟦k⟧ (-blm l+ lo (list C) (list V)) Γ 𝒞 Σ)]
    [(?)
     (define mon*
       (cond
         [(-=>_? C) mon-=>_]
         [(-St/C? C) mon-struct/c]
         [(-x/C? C) mon-x/c]
         [(-And/C? C) mon-and/c]
         [(-Or/C? C) mon-or/c]
         [(-Not/C? C) mon-not/c]
         [(-Vectorof? C) mon-vectorof]
         [(-Vector/C? C) mon-vector/c]
         [else mon-flat/c]))
     (mon* l³ ℓ W-C W-V Γ 𝒞 Σ ⟦k⟧)]))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; Stack frames
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Application
(define/memo (ap∷ [Ws : (Listof -W¹)]
                  [⟦e⟧s : (Listof -⟦e⟧!)]
                  [ρ : -ρ]
                  [l : -l]
                  [ℓ : -ℓ]
                  [⟦k⟧ : -⟦k⟧!]) : -⟦k⟧!
  (with-error-handling (⟦k⟧ A Γ 𝒞 Σ)
    (match-define (-W Vs s) A)
    (match Vs
      [(list V)
       (define Ws* (cons (-W¹ V s) Ws))
       (match ⟦e⟧s
         ['()
          (match-define (cons Wₕ Wₓs) (reverse Ws*))
          (app l ℓ Wₕ Wₓs Γ 𝒞 Σ ⟦k⟧)]
         [(cons ⟦e⟧ ⟦e⟧s*)
          (⟦e⟧ ρ Γ 𝒞 Σ (ap∷ Ws* ⟦e⟧s* ρ l ℓ ⟦k⟧))])]
      [_
       (⟦k⟧ (-blm l 'Λ (list '1-value) (list (format-symbol "~a values" (length Vs)))) Γ 𝒞 Σ)])))

(define/memo (mon.c∷ [l³ : -l³]
                     [ℓ : -ℓ]
                     [C : (U (Pairof -⟦e⟧! -ρ) -W¹)]
                     [⟦k⟧! : -⟦k⟧!]) : -⟦k⟧!
  (match-define (-l³ _ _ lo) l³)
  (with-error-handling (⟦k⟧! A Γ 𝒞 Σ)
    (match-define (-W Vs s) A)
    (match Vs
      [(list V)
       (define W-V (-W¹ V s))
       (cond [(-W¹? C) (mon l³ ℓ C W-V Γ 𝒞 Σ ⟦k⟧!)]
             [else
              (match-define (cons ⟦c⟧ ρ) C)
              (⟦c⟧ ρ Γ 𝒞 Σ (mon.v∷ l³ ℓ W-V ⟦k⟧!))])]
      [else
       (define blm (-blm lo 'Λ '(|1 value|) Vs))
       (⟦k⟧! blm Γ 𝒞 Σ)])))

(define/memo (mon.v∷ [l³ : -l³]
                     [ℓ : -ℓ]
                     [V : (U (Pairof -⟦e⟧! -ρ) -W¹)]
                     [⟦k⟧! : -⟦k⟧!]) : -⟦k⟧!
  (match-define (-l³ _ _ lo) l³)
  (with-error-handling (⟦k⟧! A Γ 𝒞 Σ)
    (match-define (-W Vs s) A)
    (match Vs
      [(list C)
       (define W-C (-W¹ C s))
       (cond [(-W¹? V) (mon l³ ℓ W-C V Γ 𝒞 Σ ⟦k⟧!)]
             [else
              (match-define (cons ⟦v⟧ ρ) V)
              (⟦v⟧ ρ Γ 𝒞 Σ (mon.c∷ l³ ℓ W-C ⟦k⟧!))])]
      [else
       (define blm (-blm lo 'Λ '(|1 value|) Vs))
       (⟦k⟧! blm Γ 𝒞 Σ)])))

;; let-values
(define/memo (let∷ [l : -l]
                   [xs : (Listof Var-Name)]
                   [⟦bnd⟧s : (Listof (Pairof (Listof Var-Name) -⟦e⟧!))]
                   [bnd-Ws : (Listof (List Var-Name -V -s))]
                   [⟦e⟧ : -⟦e⟧!]
                   [ρ : -ρ]
                   [⟦k⟧ : -⟦k⟧!]) : -⟦k⟧!
  (with-error-handling (⟦k⟧ A Γ 𝒞 Σ)
    (match-define (-W Vs s) A)
    (define n (length xs))
    (cond
      [(= n (length Vs))
       (define bnd-Ws*
         (for/fold ([acc : (Listof (List Var-Name -V -s)) bnd-Ws])
                   ([x xs] [V Vs] [sₓ (split-values s n)])
           (cons (list x V sₓ) acc)))
       (match ⟦bnd⟧s
         ['()
          (match-define (-Σ σ _ _) Σ)
          (define-values (ρ* Γ*) ; with side effect widening store
            (for/fold ([ρ : -ρ ρ] [Γ : -Γ Γ])
                      ([bnd-W bnd-Ws*])
              (match-define (list (? Var-Name? x) (? -V? Vₓ) (? -s? sₓ)) bnd-W)
              (define α (-α.x x 𝒞))
              (σ⊔! σ α Vₓ #t)
              (values (ρ+ ρ x α) (-Γ-with-aliases Γ x sₓ))))
          (⟦e⟧ ρ* Γ* 𝒞 Σ ⟦k⟧)]
         [(cons (cons xs* ⟦e⟧*) ⟦bnd⟧s*)
          (⟦e⟧* ρ Γ 𝒞 Σ (let∷ l xs* ⟦bnd⟧s* bnd-Ws* ⟦e⟧ ρ ⟦k⟧))])]
      [else
       (define blm
         (-blm l 'let-values
               (list (format-symbol "~a values" (length xs)))
               (list (format-symbol "~a values" (length Vs)))))
       (⟦k⟧ blm Γ 𝒞 Σ)])))

;; begin
(define/memo (bgn∷ [⟦e⟧s : (Listof -⟦e⟧!)] [ρ : -ρ] [⟦k⟧ : -⟦k⟧!]) : -⟦k⟧!
  (match ⟦e⟧s
    ['() ⟦k⟧]
    [(cons ⟦e⟧ ⟦e⟧s*)
     (with-error-handling (⟦k⟧ A Γ 𝒞 Σ)
       (⟦e⟧ ρ Γ 𝒞 Σ (bgn∷ ⟦e⟧s* ρ ⟦k⟧)))]))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; Helpers
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(:* mon-=>_ mon-struct/c mon-x/c mon-and/c mon-or/c mon-not/c mon-vectorof mon-vector/c mon-flat/c :
    -l³ -ℓ -W¹ -W¹ -Γ -𝒞 -Σ -⟦k⟧! → (℘ -ς))

(define (mon-=>_ l³ ℓ W-C W-V Γ 𝒞 Σ ⟦k⟧)
  (match-define (-W¹ grd c) W-C)
  (match-define (-W¹ V v) W-V)
  (match-define (-l³ l+ _ lo) l³)
  (match-define (-Σ σ _ M) Σ)
  
  (define arity
    (let ([a
           (match grd
             [(-=> αs _ _) (length αs)]
             [(-=>i _  β _)
              (match β
                [(-λ xs _) (formals-arity xs)]
                [_ #f])])])
      (define b (-b a))
      (-W¹ b b)))
  
  (define-values (Γ₁ Γ₂) (Γ+/-W∋Ws M Γ -procedure?/W W-V))
  (define-values (Γ₁₁ Γ₁₂)
    (if Γ₁
        (let ([A (V-arity V)]
              [a (-?@ 'procedure-arity v)])
          (define W-a (-W¹ (if A (-b A) -●/V) a))
          (Γ+/-W∋Ws M Γ₁ -arity-includes?/W W-a arity))
        (values #f #f)))
  (∪ (cond [Γ₁₁
            (define grd-ℓ
              (cond [(-=>? grd) (-=>-pos grd)]
                    [else (-=>i-pos grd)]))
            (define α (or (keep-if-const v) (-α.fn ℓ grd-ℓ 𝒞)))
            (define Ar (-Ar grd α l³))
            (σ⊔! σ α V #t)
            (⟦k⟧ (-W (list Ar) v) Γ₁₁ 𝒞 Σ)]
           [else ∅])
     (cond [Γ₁₂
            (define C #|HACK|#
              (match arity
                [(-W¹ (-b (? integer? n)) _)
                 (format-symbol "(arity-includes/c ~a)" n)]
                [(-W¹ (-b (arity-at-least n)) _)
                 (format-symbol "(arity-at-least/c ~a)" n)]))
            (⟦k⟧ (-blm l+ lo (list C) (list V)) Γ₁₂ 𝒞 Σ)]
           [else ∅])
     (cond [Γ₂ (⟦k⟧ (-blm l+ lo (list 'procedure?) (list V)) Γ₂ 𝒞 Σ)]
           [else ∅])))

(define (mon-struct/c l³ ℓ W-C W-V Γ 𝒞 Σ ⟦k⟧)
  (match-define (-W¹ C c) W-C)
  (match-define (-W¹ V v) W-V)
  (match-define (-l³ l+ _ lo) l³)
  (match-define (-St/C flat? s αs) C)
  (define cs (-struct/c-split c (-struct-info-arity s)))
  (define p (-st-p s))
  (define K (let ([k (-st-mk s)]) (-W¹ k k)))
  (define muts (-struct-info-mutables s))

  (define ⟦field⟧s : (Listof -⟦e⟧!)
    (for/list ([(α i) (in-indexed αs)])
      (define ac (-st-ac s (assert i exact-nonnegative-integer?)))
      (mk-app-⟦e⟧ lo ℓ (mk-rt-⟦e⟧ (-W¹ ac ac)) (list (mk-rt-⟦e⟧ (-W¹ V v))))))

  (match V ; FIXME code dup
    [(or (-St (== s) _) (-St* (== s) _ _ _))
     (cond
       [(null? ⟦field⟧s)
        (⟦k⟧ (-W (list V) v) Γ 𝒞 Σ)]
       [else
        (for/union : (℘ -ς) ([Cs (σ@/list (-Σ-σ Σ) αs)])
                   (define ⟦mon⟧s : (Listof -⟦e⟧!)
                     (for/list ([Cᵢ Cs] [cᵢ cs] [⟦field⟧ ⟦field⟧s])
                       (mk-mon-⟦e⟧ l³ ℓ (mk-rt-⟦e⟧ (-W¹ Cᵢ cᵢ)) ⟦field⟧)))
                   (define ⟦reconstr⟧ (mk-app-⟦e⟧ lo ℓ (mk-rt-⟦e⟧ K) ⟦mon⟧s))
                   (define ⟦k⟧*
                     (cond [(set-empty? muts) ⟦k⟧]
                           [else
                            (define α (-α.st (-struct-info-id s) ℓ 𝒞))
                            (wrap-st∷ s αs α l³ ⟦k⟧)]))
                   (⟦reconstr⟧ ⊥ρ Γ 𝒞 Σ ⟦k⟧*))])]
    [(-● _)
     (define ⟦chk⟧ (mk-app-⟦e⟧ lo ℓ (mk-rt-⟦e⟧ (-W¹ p p)) (list (mk-rt-⟦e⟧ W-V))))
     (define ⟦blm⟧ (mk-rt-⟦e⟧ (-blm l+ lo (list p) (list V))))
     (cond
       [(null? ⟦field⟧s)
        (define ⟦rt⟧ (mk-rt-⟦e⟧ W-V))
        (⟦chk⟧ ⊥ρ Γ 𝒞 Σ (if∷ lo ⟦rt⟧ ⟦blm⟧ ⊥ρ ⟦k⟧))]
       [else
        (for/union : (℘ -ς) ([Cs (σ@/list (-Σ-σ Σ) αs)])
          (define ⟦mon⟧s : (Listof -⟦e⟧!)
            (for/list ([Cᵢ Cs] [cᵢ cs] [⟦field⟧ ⟦field⟧s])
              (mk-mon-⟦e⟧ l³ ℓ (mk-rt-⟦e⟧ (-W¹ Cᵢ cᵢ)) ⟦field⟧)))
          (define ⟦reconstr⟧ (mk-app-⟦e⟧ lo ℓ (mk-rt-⟦e⟧ K) ⟦mon⟧s))
          (define ⟦k⟧*
            (cond
              [(set-empty? muts) ⟦k⟧]
              [else
               (define α (-α.st (-struct-info-id s) ℓ 𝒞))
               (wrap-st∷ s αs α l³ ⟦k⟧)]))
          (⟦chk⟧ ⊥ρ Γ 𝒞 Σ
           (if∷ lo ⟦reconstr⟧ ⟦blm⟧ ⊥ρ ⟦k⟧*)))])]
    [_ (⟦k⟧ (-blm l+ lo (list C) (list V)) Γ 𝒞 Σ)]))

(define (mon-x/c l³ ℓ W-C W-V Γ 𝒞 Σ ⟦k⟧)
  (match-define (-W¹ C c) W-C)
  (match-define (-W¹ V v) W-V)
  (match-define (-x/C (and α (-α.x/c ℓₓ))) C)
  (define x (- ℓₓ)) ; FIXME hack
  (define 𝐱 (-x x))
  (match-define (-Σ σ σₖ _) Σ)
  (define 𝒞* (𝒞+ 𝒞 ((inst cons -ℓ -ℓ) ℓₓ ℓ)))
  (for/set: : (℘ -ς) ([C* (σ@ᵥ σ α)])
    (define αₖ
      (let ([W-C* (-W¹ C* c)]
            [W-V* (-W¹ V 𝐱)])
        (-ℳ l³ ℓ W-C* W-V*)))
    (define κ
      (let ([bnd #|FIXME hack|# (-binding 'values (list x) (if v (hasheq x v) (hasheq)))])
        (-κ ⟦k⟧ Γ 𝒞 bnd)))
    (vm⊔! σₖ αₖ κ)
    (define Γ* ; HACK: drop all tails for now
      (match-let ([(-Γ φs as γs) Γ])
        (invalidate (-Γ φs as '()) x)))
    (-ς↑ αₖ Γ* 𝒞* #;𝒞)))

(define (mon-and/c l³ ℓ W-C W-V Γ 𝒞 Σ ⟦k⟧)
  (match-define (-Σ σ _ _) Σ)
  (match-define (-W¹ (-And/C _ α₁ α₂) c) W-C)
  (match-define (list c₁ c₂) (-app-split c 'and/c 2))
  (for/union : (℘ -ς) ([C₁ (σ@ᵥ σ α₁)] [C₂ (σ@ᵥ σ α₂)])
    (mon l³ ℓ (-W¹ C₁ c₁) W-V Γ 𝒞 Σ 
         (mon.c∷ l³ ℓ (-W¹ C₂ c₂) ⟦k⟧))))

(define (mon-or/c l³ ℓ W-C W-V Γ 𝒞 Σ ⟦k⟧)
  (match-define (-Σ σ _ _) Σ)
  (match-define (-l³ l+ _ lo) l³)
  (match-define (-W¹ (-Or/C flat? α₁ α₂) c) W-C)
  (define-values (c₁ c₂)
    (match-let ([(list s₁ s₂) (-app-split c 'or/c 2)])
      (values (or s₁ (and (-e? α₁) α₁))
              (or s₂ (and (-e? α₂) α₂)))))
  
  (: chk-or/c : -W¹ -W¹ → (℘ -ς))
  (define (chk-or/c W-fl W-ho)
    (flat-chk lo ℓ W-fl W-V Γ 𝒞 Σ
              (mon-or/c∷ l³ ℓ W-fl W-ho W-V ⟦k⟧)))

  (for*/union : (℘ -ς) ([C₁ (σ@ᵥ σ α₁)] [C₂ (σ@ᵥ σ α₂)])
    (define W-C₁ (-W¹ C₁ c₁))
    (define W-C₂ (-W¹ C₂ c₂))
    (cond [(C-flat? C₁) (chk-or/c W-C₁ W-C₂)]
          [(C-flat? C₂) (chk-or/c W-C₂ W-C₁)]
          [else (error 'or/c "No more than 1 higher-order disjunct for now")])))

(define (mon-not/c l³ ℓ W-C W-V Γ 𝒞 Σ ⟦k⟧)
  (match-define (-l³ l+ _ lo) l³)
  (match-define (-W¹ (and C (-Not/C α)) c) W-C)
  (match-define (-W¹ V _) W-V)
  (match-define (list c*) (-app-split c 'not/c 1))
  (define ⟦k⟧*
    (let ([⟦ok⟧ (mk-rt-⟦e⟧ W-V)]
          [⟦er⟧ (mk-rt-⟦e⟧ (-blm l+ lo (list C) (list V)))])
      (if∷ lo ⟦er⟧ ⟦ok⟧ ⊥ρ ⟦k⟧)))
  (for/union : (℘ -ς) ([C* (σ@ᵥ (-Σ-σ Σ) α)])
    (assert C* C-flat?)
    (define W-C* (-W¹ C* c*))
    (app lo ℓ W-C* (list W-V) Γ 𝒞 Σ ⟦k⟧*)))

(define (mon-vectorof l³ ℓ W-C W-V Γ 𝒞 Σ ⟦k⟧)
  (match-define (-Σ σ _ _) Σ)
  (match-define (-l³ l+ _ lo) l³)
  (match-define (-W¹ Vᵥ sᵥ) W-V)
  (match-define (-W¹ (-Vectorof α) _) W-C)
  (define c (and (-e? α) α))
  (define ⟦rt⟧ (mk-rt-⟦e⟧ W-V))
  
  (match Vᵥ
    [(-Vector αs)
     (define Wₕᵥ (-W¹ (σ@¹ σ (-α.def havoc-𝒾)) havoc-𝒾))
     (for*/union : (℘ -ς) ([C (σ@ᵥ σ α)] [Vs (σ@/list σ αs)])
       (define ⟦hv⟧s : (Listof -⟦e⟧!)
         (for/list ([(V* i) (in-indexed Vs)])
           (define ⟦chk⟧
             (mk-mon-⟦e⟧ l³ ℓ
                         (mk-rt-⟦e⟧ (-W¹ C c))
                         (mk-rt-⟦e⟧ (-W¹ V* (-?@ 'vector-ref sᵥ (-b i))))))
           (mk-app-⟦e⟧ lo ℓ (mk-rt-⟦e⟧ Wₕᵥ) (list ⟦chk⟧))))
       (match-define (cons ⟦e⟧ ⟦e⟧s) (append ⟦hv⟧s (list (mk-erase-⟦e⟧ αs) ⟦rt⟧)))
       (⟦e⟧ ⊥ρ Γ 𝒞 Σ (bgn∷ ⟦e⟧s ⊥ρ ⟦k⟧)))]
    [(-Vector/hetero αs l³*)
     (define cs : (Listof -s) (for/list ([α αs]) (and (-e? α) α)))
     (for*/union : (℘ -ς) ([C (σ@ᵥ σ α)] [Cs (σ@/list σ αs)])
       (define ⟦chk⟧s : (Listof -⟦e⟧!)
         (for/list ([C* Cs] [(c* i) (in-indexed cs)])
           (define ⟦inner⟧
             (mk-mon-⟦e⟧ l³* ℓ
                         (mk-rt-⟦e⟧ (-W¹ C* c*))
                         (mk-rt-⟦e⟧ (-W¹ -●/V (-?@ 'vector-ref sᵥ (-b i))))))
           (mk-mon-⟦e⟧ l³ ℓ (mk-rt-⟦e⟧ (-W¹ C c)) ⟦inner⟧)))
       (match-define (cons ⟦e⟧ ⟦e⟧s) (append ⟦chk⟧s (list ⟦rt⟧)))
       (⟦e⟧ ⊥ρ Γ 𝒞 Σ (bgn∷ ⟦e⟧s ⊥ρ ⟦k⟧)))]
    [(-Vector/homo α* l³*)
     (define c* (and (-e? α*) α*))
     (for*/union : (℘ -ς) ([C* (σ@ᵥ σ α*)] [C (σ@ᵥ σ α)])
       (define ⟦chk⟧
         (let ([⟦inner⟧
                (mk-mon-⟦e⟧ l³* ℓ (mk-rt-⟦e⟧ (-W¹ C* c*)) (mk-rt-⟦e⟧ (-W¹ -●/V (-x #|FIXME|# -1))))])
           (mk-mon-⟦e⟧ l³ ℓ (mk-rt-⟦e⟧ (-W¹ C c)) ⟦inner⟧)))
       (⟦chk⟧ ⊥ρ Γ 𝒞 Σ (bgn∷ (list ⟦rt⟧) ⊥ρ ⟦k⟧)))]
    [(-● _)
     (define ⟦er⟧ (mk-rt-⟦e⟧ (-blm l+ lo (list 'vector?) (list Vᵥ))))
     (app lo ℓ -vector?/W (list W-V) Γ 𝒞 Σ
          (if∷ lo ⟦rt⟧ ⟦er⟧ ⊥ρ ⟦k⟧))]
    [_ (⟦k⟧ (-blm l+ lo (list 'vector?) (list Vᵥ)) Γ 𝒞 Σ)]))

(define (mon-vector/c l³ ℓ W-C W-V Γ 𝒞 Σ ⟦k⟧)
  (match-define (-Σ σ _ _) Σ)
  (match-define (-l³ l+ _ lo) l³)
  (match-define (-W¹ Vᵥ vᵥ) W-V)
  (match-define (-W¹ C  c ) W-C)
  (match-define (-Vector/C αs) C)
  (define n (length αs))
  (define N (let ([b (-b n)]) (-W¹ b b)))
  (define cs
    (let ([ss (-app-split c 'vector/c n)])
      (for/list : (Listof -s) ([s ss] [α αs])
        (or s (and (-e? α) α)))))
  (define ⟦chk-vct⟧ (mk-app-⟦e⟧ lo ℓ (mk-rt-⟦e⟧ -vector?/W) (list (mk-rt-⟦e⟧ W-V))))
  (define ⟦chk-len⟧
    (let ([⟦len⟧ (mk-app-⟦e⟧ lo ℓ (mk-rt-⟦e⟧ -vector-length/W) (list (mk-rt-⟦e⟧ W-V)))])
      (mk-app-⟦e⟧ lo ℓ (mk-rt-⟦e⟧ -=/W) (list (mk-rt-⟦e⟧ N) ⟦len⟧))))
  (define ⟦blm-vct⟧ (mk-rt-⟦e⟧ (-blm l+ lo (list 'vector?) (list Vᵥ))))
  (define ⟦blm-len⟧ (mk-rt-⟦e⟧ (-blm l+ lo (list (format-symbol "length ~a" n)) (list Vᵥ))))
  (define ⟦mk⟧
    (let ([V* (-Vector/hetero αs l³)])
      (mk-rt-⟦e⟧ (-W (list V*) vᵥ))))
  (define Wₕᵥ (-W¹ (σ@¹ σ (-α.def havoc-𝒾)) havoc-𝒾))
  (for*/union : (℘ -ς) ([Cs (σ@/list σ αs)])
     (define ⟦hv-fld⟧s : (Listof -⟦e⟧!)
       (for/list ([C* Cs] [(c* i) (in-indexed cs)])
         (define W-C* (-W¹ C* c*))
         (define Wᵢ (let ([b (-b i)]) (-W¹ b b)))
         (define ⟦ref⟧
           (mk-app-⟦e⟧ lo ℓ
                       (mk-rt-⟦e⟧ -vector-ref/W)
                       (list (mk-rt-⟦e⟧ W-V)
                             (mk-rt-⟦e⟧ Wᵢ))))
         (define ⟦mon⟧ (mk-mon-⟦e⟧ l³ ℓ (mk-rt-⟦e⟧ W-C*) ⟦ref⟧))
         (mk-app-⟦e⟧ havoc-path ℓ (mk-rt-⟦e⟧ Wₕᵥ) (list ⟦mon⟧))))
     (define ⟦erase⟧
       (match Vᵥ
         [(-Vector αs) (mk-erase-⟦e⟧ αs)]
         [_ ⟦void⟧]))
     (define ⟦wrp⟧ (mk-begin-⟦e⟧ (append ⟦hv-fld⟧s (list ⟦erase⟧ ⟦mk⟧))))
     (⟦chk-vct⟧ ⊥ρ Γ 𝒞 Σ
      (if∷ lo (mk-if-⟦e⟧ lo ⟦chk-len⟧ ⟦wrp⟧ ⟦blm-len⟧) ⟦blm-vct⟧ ⊥ρ ⟦k⟧))))

(define (mon-flat/c l³ ℓ W-C W-V Γ 𝒞 Σ ⟦k⟧)
  (match-define (-l³ l+ _ lo) l³)
  (match-define (-W¹ C _) W-C)
  (match-define (-W¹ V v) W-V)
  (app lo +ℓ₀ W-C (list W-V) Γ 𝒞 Σ
       (if.flat/c∷ (-W (list V) v) (-blm l+ lo (list C) (list V)) ⟦k⟧)))

(: flat-chk : -l -ℓ -W¹ -W¹ -Γ -𝒞 -Σ -⟦k⟧! → (℘ -ς))
(define (flat-chk l ℓ W-C W-V Γ 𝒞 Σ ⟦k⟧)
  (match-define (-Σ σ σₖ _) Σ)
  (match-define (-W¹ C c) W-C)
  (match-define (-W¹ V v) W-V)
  (match C
    [(-And/C _ α₁ α₂)
     (define-values (c₁ c₂)
       (match-let ([(list s₁ s₂) (-app-split c 'and/c 2)])
         (values (or s₁ (α->s α₁)) (or s₂ (α->s α₂)))))
     (for*/union : (℘ -ς) ([C₁ (σ@ᵥ σ α₁)] [C₂ (σ@ᵥ σ α₂)])
       (define W-C₁ (-W¹ C₁ c₁))
       (define W-C₂ (-W¹ C₂ c₂))
       (flat-chk l ℓ W-C₁ W-V Γ 𝒞 Σ (fc-and/c∷ l ℓ W-C₁ W-C₂ ⟦k⟧)))]
    [(-Or/C _ α₁ α₂)
     (define-values (c₁ c₂)
       (match-let ([(list s₁ s₂) (-app-split c 'or/c 2)])
         (values (or s₁ (α->s α₁)) (or s₂ (α->s α₂)))))
     (for*/union : (℘ -ς) ([C₁ (σ@ᵥ σ α₁)] [C₂ (σ@ᵥ σ α₂)])
       (define W-C₁ (-W¹ C₁ c₁))
       (define W-C₂ (-W¹ C₂ c₁))
       (flat-chk l ℓ W-C₁ W-V Γ 𝒞 Σ (fc-or/c∷ l ℓ W-C₁ W-C₂ W-V ⟦k⟧)))]
    [(-Not/C α)
     (define c*
       (match-let ([(list s) (-app-split c 'not/c 1)])
         (or s (α->s α))))
     (for/union : (℘ -ς) ([C* (σ@ᵥ σ α)])
       (define W-C* (-W¹ C* c*))
       (flat-chk l ℓ W-C* W-V Γ 𝒞 Σ (fc-not/c∷ l ℓ W-C* W-V ⟦k⟧)))]
    [(-St/C _ s αs)
     (define cs
       (let ([ss (-struct/c-split c (-struct-info-arity s))])
         (for/list : (Listof -s) ([s ss] [α αs])
           (or s (α->s α)))))
     (for/union : (℘ -ς) ([Cs (σ@/list σ αs)])
       (define ⟦chk-field⟧s : (Listof -⟦e⟧!)
         (for/list ([Cᵢ Cs] [(cᵢ i) (in-indexed cs)])
           (define ac (-st-ac s (assert i exact-nonnegative-integer?)))
           (define ⟦ref⟧ᵢ (mk-app-⟦e⟧ 'Λ ℓ (mk-rt-⟦e⟧ (-W¹ ac ac)) (list (mk-rt-⟦e⟧ W-V))))
           (mk-fc-⟦e⟧ l ℓ (mk-rt-⟦e⟧ (-W¹ Cᵢ cᵢ)) ⟦ref⟧ᵢ)))
       (match ⟦chk-field⟧s
         ['()
          (define p (-st-p s))
          (define ⟦rt⟧ (mk-rt-⟦e⟧ (-W (list -tt (V+ σ V p)) (-?@ 'values -tt v))))
          (app l ℓ (-W¹ p p) (list W-V) Γ 𝒞 Σ (if∷ l ⟦rt⟧ ⟦ff⟧ ⊥ρ ⟦k⟧))]
         [(cons ⟦chk-field⟧ ⟦chk-field⟧s*)
          (⟦chk-field⟧ ⊥ρ Γ 𝒞 Σ (fc-struct/c∷ l ℓ s '() ⟦chk-field⟧s* ⊥ρ ⟦k⟧))]))]
    [(-x/C α)
     (match-define (-W¹ C c) W-C)
     (match-define (-W¹ V v) W-V)
     (match-define (-x/C (and α (-α.x/c ℓₓ))) C)
     (define x (- ℓₓ)) ; FIXME hack
     (define 𝐱 (-x x))
     (define 𝒞* (𝒞+ 𝒞 (cons ℓₓ ℓ)))
     (for/set: : (℘ -ς) ([C* (σ@ᵥ σ α)])
       (define W-C* (-W¹ C* c))
       (define W-V* (-W¹ V 𝐱))
       (define bnd (-binding 'fc (list x) (if v (hasheq x v) (hasheq))))
       (define κ (-κ ⟦k⟧ Γ 𝒞 bnd))
       (define αₖ (-ℱ l ℓ W-C* W-V*))
       (vm⊔! σₖ αₖ κ)
       (-ς↑ αₖ Γ 𝒞* #;𝒞))]
    [_
     (define ⟦ap⟧ (mk-app-⟦e⟧ l ℓ (mk-rt-⟦e⟧ W-C) (list (mk-rt-⟦e⟧ W-V))))
     (define ⟦rt⟧ (mk-rt-⟦e⟧ (-W (list -tt (V+ σ V C)) (-?@ 'values -tt v))))
     (⟦ap⟧ ⊥ρ Γ 𝒞 Σ (if∷ l ⟦rt⟧ ⟦ff⟧ ⊥ρ ⟦k⟧))]))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; Helper frames
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define/memo (mon-or/c∷ [l³ : -l³]
                        [ℓ : -ℓ]
                        [Wₗ : -W¹]
                        [Wᵣ : -W¹]
                        [W-V : -W¹]
                        [⟦k⟧! : -⟦k⟧!]) : -⟦k⟧!
  (with-error-handling (⟦k⟧! A Γ 𝒞 Σ)
    (match-define (-W Vs s) A)
    (match Vs
      [(list (-b #f))
       (mon l³ ℓ Wᵣ W-V Γ 𝒞 Σ ⟦k⟧!)]
      [(list (-b #t) V)
       (match-define (-W¹ Cₗ _) Wₗ)
       (match-define (-@ 'values (list _ v) _) s)
       (⟦k⟧! (-W (list (V+ (-Σ-σ Σ) V Cₗ)) v) Γ 𝒞 Σ)])))

(define/memo (if.flat/c∷ [W-V : -W] [blm : -blm] [⟦k⟧! : -⟦k⟧!]) : -⟦k⟧!
  (with-error-handling (⟦k⟧! A Γ 𝒞 Σ)
    (match-define (-W Vs v) A)
    (match Vs
      [(list V)
       (with-Γ+/- ([(Γ₁ Γ₂) (Γ+/-V (-Σ-M Σ) Γ V v)])
         #:true  (⟦k⟧! W-V Γ₁ 𝒞 Σ)
         #:false (⟦k⟧! blm Γ₂ 𝒞 Σ))]
      [_
       (match-define (-blm _ lo _ _) blm)
       (⟦k⟧! (-blm lo 'Λ '(|1 value|) Vs) Γ 𝒞 Σ)])))

;; Conditional
(define/memo (if∷ [l : -l] [⟦e⟧₁ : -⟦e⟧!] [⟦e⟧₂ : -⟦e⟧!] [ρ : -ρ] [⟦k⟧ : -⟦k⟧!]) : -⟦k⟧!
  (with-error-handling (⟦k⟧ A Γ 𝒞 Σ)
    (match-define (-W Vs s) A)
    (match Vs
      [(list V)
       (with-Γ+/- ([(Γ₁ Γ₂) (Γ+/-V (-Σ-M Σ) Γ V s)])
         #:true  (⟦e⟧₁ ρ Γ₁ 𝒞 Σ ⟦k⟧)
         #:false (⟦e⟧₂ ρ Γ₂ 𝒞 Σ ⟦k⟧))]
      [_ (⟦k⟧ (-blm l 'Λ '(1-value) (list (format-symbol "~a values" (length Vs)))) Γ 𝒞 Σ)])))

(define/memo (and∷ [l : -l] [⟦e⟧s : (Listof -⟦e⟧!)] [ρ : -ρ] [⟦k⟧! : -⟦k⟧!]) : -⟦k⟧!
  (match ⟦e⟧s
    ['() ⟦k⟧!]
    [(cons ⟦e⟧ ⟦e⟧s*)
     (if∷ l ⟦e⟧ ⟦ff⟧ ρ (and∷ l ⟦e⟧s* ρ ⟦k⟧!))]))

(define/memo (or∷ [l : -l] [⟦e⟧s : (Listof -⟦e⟧!)] [ρ : -ρ] [⟦k⟧! : -⟦k⟧!]) : -⟦k⟧!
  (match ⟦e⟧s
    ['() ⟦k⟧!]
    [(cons ⟦e⟧ ⟦e⟧s*) ; TODO propagate value instead
     (if∷ l ⟦tt⟧ ⟦e⟧ ρ (or∷ l ⟦e⟧s* ρ ⟦k⟧!))]))

(define/memo (neg∷ [l : -l] [⟦k⟧! : -⟦k⟧!]) : -⟦k⟧! (if∷ l ⟦ff⟧ ⟦tt⟧ ⊥ρ ⟦k⟧!))

(define/memo (wrap-st∷ [s : -struct-info]
                       [αs : (Listof -α)]
                       [α : -α.st]
                       [l³ : -l³]
                       [⟦k⟧! : -⟦k⟧!]) : -⟦k⟧!
  (define muts (-struct-info-mutables s))
  (define αs* : (Listof (Option -α))
    (for/list ([(α i) (in-indexed αs)])
      (and (∋ muts i) α)))
  (define V* (-St* s αs* α l³))
  (with-error-handling (⟦k⟧! A Γ 𝒞 Σ)
    (match-define (-W Vs s) A)
    (match-define (list V) Vs) ; only used internally, should be safe
    (σ⊔! (-Σ-σ Σ) α V #t)
    (⟦k⟧! (-W (list V*) s) Γ 𝒞 Σ)))

(define/memo (fc-and/c∷ [l : -l]
                        [ℓ : -ℓ]
                        [W-C₁ : -W¹]
                        [W-C₂ : -W¹]
                        [⟦k⟧! : -⟦k⟧!]) : -⟦k⟧!
  (with-error-handling (⟦k⟧! A Γ 𝒞 Σ)
    (match-define (-W Vs s) A)
    (match Vs
      [(list (-b #f)) (⟦k⟧! -False/W Γ 𝒞 Σ)]
      [(list (-b #t) V)
       (match-define (-@ 'values (list _ sᵥ) _) s)
       (match-define (-W¹ C₁ _) W-C₁)
       (flat-chk l ℓ W-C₂ (-W¹ (V+ (-Σ-σ Σ) V C₁) sᵥ) Γ 𝒞 Σ ⟦k⟧!)])))

(define/memo (fc-or/c∷ [l : -l]
                       [ℓ : -ℓ]
                       [W-C₁ : -W¹]
                       [W-C₂ : -W¹]
                       [W-V : -W¹]
                       [⟦k⟧! : -⟦k⟧!]) : -⟦k⟧!
  (with-error-handling (⟦k⟧! A Γ 𝒞 Σ)
    (match-define (-W Vs s) A)
    (match Vs
      [(list (-b #f))
       (flat-chk l ℓ W-C₂ W-V Γ 𝒞 Σ ⟦k⟧!)]
      [(list (-b #t) V)
       (match-define (-W¹ C₁ _) W-C₁)
       (⟦k⟧! (-W (list -tt (V+ (-Σ-σ Σ) V C₁)) s) Γ 𝒞 Σ)])))

(define/memo (fc-not/c∷ [l : -l]
                        [ℓ : -ℓ]
                        [W-C* : -W¹]
                        [W-V : -W¹]
                        [⟦k⟧! : -⟦k⟧!]) : -⟦k⟧!
  (with-error-handling (⟦k⟧! A Γ 𝒞 Σ)
    (match-define (-W Vs s) A)
    (match Vs
      [(list (-b #f))
       (match-define (-W¹ V v) W-V)
       (⟦k⟧! (-W (list -tt V) (-?@ 'values -tt v)) Γ 𝒞 Σ)]
      [(list (-b #t) V)
       (⟦k⟧! -False/W Γ 𝒞 Σ)])))

(define/memo (fc-struct/c∷ [l : -l]
                           [ℓ : -ℓ]
                           [s : -struct-info]
                           [W-Vs-rev : (Listof -W¹)]
                           [⟦e⟧s : (Listof -⟦e⟧!)]
                           [ρ : -ρ]
                           [⟦k⟧! : -⟦k⟧!]) : -⟦k⟧!
  (with-error-handling (⟦k⟧! A Γ 𝒞 Σ)
    (match-define (-W¹ Vs s) A)
    (match Vs
      [(list (-b #f))
       (⟦k⟧! -False/W Γ 𝒞 Σ)]
      [(list (-b #t) V*)
       (match-define (-@ 'values (list _ v) _) s)
       (match ⟦e⟧s
         ['()
          (define ⟦k⟧*
            (let ([k (-st-mk s)])
              (ap∷ l ℓ (append W-Vs-rev (list (-W¹ k k))) '() ⊥ρ
                   (ap∷ l ℓ (list (-W¹ -tt -tt) (-W¹ 'values 'values)) '() ⊥ρ ⟦k⟧!))))
          (⟦k⟧* (-W (list V*) v) Γ 𝒞 Σ)]
         [(cons ⟦e⟧ ⟦e⟧s*)
          (define W* (-W¹ V* v))
          (⟦e⟧ ρ Γ 𝒞 Σ (fc-struct/c∷ l ℓ s (cons W* W-Vs-rev) ⟦e⟧s* ρ ⟦k⟧!))])])))

(define/memo (fc.v∷ [l : -l]
                    [ℓ : -ℓ]
                    [⟦v⟧! : -⟦e⟧!]
                    [ρ : -ρ]
                    [⟦k⟧! : -⟦k⟧!]) : -⟦k⟧!
  (with-error-handling (⟦k⟧! A Γ 𝒞 Σ)
    (match-define (-W Vs s) A)
    (match Vs
      [(list C)
       (⟦v⟧! ρ Γ 𝒞 Σ (fc.c∷ l ℓ (-W¹ C s) ⟦k⟧!))]
      [_
       (define blm (-blm l 'Λ '(|1 value|) Vs))
       (⟦k⟧! blm Γ 𝒞 Σ)])))

(define/memo (fc.c∷ [l : -l]
                    [ℓ : -ℓ]
                    [W-C : -W¹]
                    [⟦k⟧! : -⟦k⟧!]) : -⟦k⟧!
  (with-error-handling (⟦k⟧! A Γ 𝒞 Σ)
    (match-define (-W Vs s) A)
    (match Vs
      [(list V)
       (flat-chk l ℓ W-C (-W¹ V s) Γ 𝒞 Σ ⟦k⟧!)]
      [_
       (define blm (-blm l 'Λ '(|1 value|) Vs))
       (⟦k⟧! blm Γ 𝒞 Σ)])))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; Helper expressions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define/memo (mk-mon-⟦e⟧ [l³ : -l³] [ℓ : -ℓ] [⟦c⟧ : -⟦e⟧!] [⟦e⟧ : -⟦e⟧!]) : -⟦e⟧!
  (λ (ρ Γ 𝒞 Σ ⟦k⟧!)
    (⟦c⟧ ρ Γ 𝒞 Σ (mon.v∷ l³ ℓ (cons ⟦e⟧ ρ) ⟦k⟧!))))

(define/memo (mk-app-⟦e⟧ [l : -l] [ℓ : -ℓ] [⟦f⟧ : -⟦e⟧!] [⟦x⟧s : (Listof -⟦e⟧!)]) : -⟦e⟧!
  (λ (ρ Γ 𝒞 Σ ⟦k⟧!)
    (⟦f⟧ ρ Γ 𝒞 Σ (ap∷ '() ⟦x⟧s ρ l ℓ ⟦k⟧!))))

(define/memo (mk-rt-⟦e⟧ [A : (U -A -W¹)]) : -⟦e⟧!
  (match A
    [(-W¹ V v) (mk-rt-⟦e⟧ (-W (list V) v))]
    [(? -A?) (λ (_ Γ 𝒞 Σ ⟦k⟧!) (⟦k⟧! A Γ 𝒞 Σ))]))

(define/memo (mk-erase-⟦e⟧ [αs : (Listof -α)]) : -⟦e⟧!
  (λ (ρ Γ 𝒞 Σ ⟦k⟧!)
    (match-define (-Σ σ _ _) Σ)
    (for ([α αs]) ; TODO: remove other concrete values?
      (σ⊔! σ α -●/V #f))
    (⟦k⟧! -Void/W Γ 𝒞 Σ)))

(define/memo (mk-begin-⟦e⟧ [⟦e⟧s : (Listof -⟦e⟧!)]) : -⟦e⟧!
  (match ⟦e⟧s
    ['() ⟦void⟧]
    [(cons ⟦e⟧ ⟦e⟧s*)
     (λ (ρ Γ 𝒞 Σ ⟦k⟧!)
       (⟦e⟧ ρ Γ 𝒞 Σ (bgn∷ ⟦e⟧s* ρ ⟦k⟧!)))]))

(define/memo (mk-if-⟦e⟧ [l : -l]
                       [⟦e⟧₁ : -⟦e⟧!]
                       [⟦e⟧₂ : -⟦e⟧!]
                       [⟦e⟧₃ : -⟦e⟧!]) : -⟦e⟧!
  (λ (ρ Γ 𝒞 Σ ⟦k⟧!)
    (⟦e⟧₁ ρ Γ 𝒞 Σ (if∷ l ⟦e⟧₂ ⟦e⟧₃ ρ ⟦k⟧!))))

(define/memo (mk-fc-⟦e⟧ [l : -l]
                       [ℓ : -ℓ]
                       [⟦c⟧! : -⟦e⟧!]
                       [⟦v⟧! : -⟦e⟧!]) : -⟦e⟧!
  (λ (ρ Γ 𝒞 Σ ⟦k⟧!)
    (⟦c⟧! ρ Γ 𝒞 Σ (fc.v∷ l ℓ ⟦v⟧! ρ ⟦k⟧!))))
