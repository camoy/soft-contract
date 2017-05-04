#lang typed/racket/base

(provide prim-runtime@)
(require racket/match
         racket/set
         syntax/parse/define
         typed/racket/unit
         set-extras
         "../utils/main.rkt"
         "../ast/main.rkt"
         "../runtime/main.rkt"
         "../signatures.rkt"
         "signatures.rkt")

(define-unit prim-runtime@
  (import proof-system^ widening^)
  (export prim-runtime^)

  (: unchecked-ac : -σ -Γ -st-ac -W¹ → (℘ -W¹))
  ;; unchecked struct accessor, assuming the value is already checked to be the right struct.
  ;; This is only for use internally, so it's safe (though imprecise) to ignore field wraps
  (define (unchecked-ac σ Γ ac W)
    (define-set seen : ⟪α⟫ #:eq? #t #:as-mutable-hash? #t)
    (match-define (-W¹ V s) W)
    (match-define (-st-ac 𝒾 i) ac)
    (define φs (-Γ-facts Γ))
    (define s* (?t@ ac s))
    (let go ([V : -V V])
      (match V
        [(-St (== 𝒾) αs)
         (for/set: : (℘ -W¹) ([V* (in-set (σ@ σ (list-ref αs i)))]
                              #:when (plausible-V-t? φs V* s*))
           (-W¹ V* s*))]
        [(-St* (-St/C _ (== 𝒾) _) α _)
         (cond [(seen-has? α) ∅]
               [else
                (seen-add! α)
                (for/union : (℘ -W¹) ([V (in-set (σ@ σ α))]
                                      #:when (plausible-V-t? φs V s))
                           (go V))])]
        [(? -●?) {set (-W¹ -●.V s*)}]
        [_ ∅])))

  (: ⊢?/quick : -R -σ (℘ -t) -o -W¹ * → Boolean)
  ;; Perform a relatively cheap check (i.e. no SMT call) if `(o W ...)` returns `R`
  (define (⊢?/quick R σ Γ o . Ws)
    (define-values (Vs ss) (unzip-by -W¹-V -W¹-t Ws))
    (eq? R (first-R (apply p∋Vs σ o Vs)
                    (Γ⊢t Γ (apply ?t@ o ss)))))

  (: implement-predicate : -M -σ -Γ Symbol (Listof -W¹) → (℘ -ΓA))
  (define (implement-predicate M σ Γ o Ws)
    (define ss (map -W¹-t Ws))
    (define A
      (case (apply MΓ⊢oW M σ Γ o Ws)
        [(✓) -tt.Vs]
        [(✗) -ff.Vs]
        [(?) -Bool.Vs]))
    {set (-ΓA (-Γ-facts Γ) (-W A (apply ?t@ o ss)))})

  (define/memoeq (make-total-pred [n : Index]) : (Symbol → -⟦o⟧)
    (λ (o)
      (λ (⟪ℋ⟫ ℒ Σ Γ Ws)
        (cond [(equal? n (length Ws))
               (match-define (-Σ σ _ M) Σ)
               (implement-predicate M σ Γ o Ws)]
              [else
               {set (-ΓA (-Γ-facts Γ) (blm-arity (-ℒ-app ℒ) o n (map -W¹-V Ws)))}]))))

  (define alias-table : (HashTable Symbol Symbol) (make-hasheq))
  (define alias-internal-table : (HashTable Symbol (U -st-mk -st-p -st-ac -st-mut)) (make-hasheq))
  (define const-table : (HashTable Symbol -b) (make-hasheq))
  (define prim-table  : (HashTable Symbol -⟦o⟧) (make-hasheq))
  (define opq-table   : (HashTable Symbol -●) (make-hasheq))
  (define debug-table : (HashTable Symbol Any) (make-hasheq))

  (: get-prim : Symbol → (Option -⟦o⟧))
  (define (get-prim o) (hash-ref prim-table o #f))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; Helpers for some of the primitives
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (: implement-mem : Symbol -⟪ℋ⟫ -ℒ -Σ -Γ -W¹ -W¹ → (℘ -ΓA))
  (define (implement-mem o ⟪ℋ⟫ ℒ Σ Γ Wₓ Wₗ)
    (match-define (-W¹ Vₓ sₓ) Wₓ)
    (match-define (-W¹ Vₗ sₗ) Wₗ)
    (define sₐ (?t@ o sₓ sₗ))
    (define σ (-Σ-σ Σ))
    (match Vₗ
      [(-Cons _ _)
       (cond
         [(definitely-not-member? σ Vₓ Vₗ)
          {set (-ΓA (-Γ-facts Γ) (-W -ff.Vs sₐ))}]
         [else
          (define αₕ (-α->⟪α⟫ (-α.fld -𝒾-cons ℒ ⟪ℋ⟫ 0)))
          (define αₜ (-α->⟪α⟫ (-α.fld -𝒾-cons ℒ ⟪ℋ⟫ 1)))
          (define Vₜ (-Cons αₕ αₜ))
          (for ([Vₕ (extract-list-content σ Vₗ)])
            (σ⊕V! Σ αₕ Vₕ))
          (σ⊕V! Σ αₜ Vₜ)
          (σ⊕V! Σ αₜ -null)
          (define Ans {set (-ΓA (-Γ-facts Γ) (-W (list Vₜ) sₐ))})
          (cond [(definitely-member? σ Vₓ Vₗ) Ans]
                [else (set-add Ans (-ΓA (-Γ-facts Γ) (-W -ff.Vs sₐ)))])])]
      [(-b '()) {set (-ΓA (-Γ-facts Γ) (-W -ff.Vs sₐ))}]
      [_ {set (-ΓA (-Γ-facts Γ) (-W (list (-● {set 'list? -cons?})) sₐ))
              (-ΓA (-Γ-facts Γ) (-W -ff.Vs sₐ))}]))

  (: definitely-member? : -σ -V -St → Boolean)
  (define (definitely-member? σ V Vₗ)
    (let loop ([Vₗ : -V Vₗ] [seen : (℘ -V) ∅])
      (cond
        [(∋ seen Vₗ) #f]
        [else
         (match Vₗ
           [(-Cons αₕ αₜ)
            (or (for/and : Boolean ([Vₕ (σ@ σ αₕ)]) (definitely-equal? σ V Vₕ))
                (for/and : Boolean ([Vₜ (σ@ σ αₜ)]) (loop Vₜ (set-add seen Vₗ))))]
           [_ #f])])))

  (: definitely-not-member? : -σ -V -St → Boolean)
  (define (definitely-not-member? σ V Vₗ)
    (let loop ([Vₗ : -V Vₗ] [seen : (℘ -V) ∅])
      (cond
        [(∋ seen Vₗ) #t]
        [else
         (match Vₗ
           [(-Cons αₕ αₜ)
            (and (for/and : Boolean ([Vₕ (σ@ σ αₕ)]) (definitely-not-equal? σ V Vₕ))
                 (for/and : Boolean ([Vₜ (σ@ σ αₜ)]) (loop Vₜ (set-add seen Vₗ))))]
           [(-b (list)) #t]
           [_ #f])])))


  (: definitely-equal? : -σ -V -V → Boolean)
  (define (definitely-equal? σ V₁ V₂)
    (let loop ([V₁ : -V V₁] [V₂ : -V V₂] [seen : (℘ (Pairof -V -V)) ∅])
      (cond
        [(∋ seen (cons V₁ V₂)) #t]
        [else
         (match* (V₁ V₂)
           [((-b b₁) (-b b₂)) (equal? b₁ b₂)]
           [((-St 𝒾 αs₁) (-St 𝒾 αs₂))
            (for/and : Boolean ([α₁ : ⟪α⟫ αs₁] [α₂ : ⟪α⟫ αs₂])
              (define Vs₁ (σ@ σ α₁))
              (define Vs₂ (σ@ σ α₂))
              (for/and : Boolean ([V₁* Vs₁]) ; can't use for*/and :(
                (for/and : Boolean ([V₂* Vs₂])
                  (loop V₁* V₂* (set-add seen (cons V₁ V₂))))))]
           [(_ _) #f])])))

  (: definitely-not-equal? : -σ -V -V → Boolean)
  (define (definitely-not-equal? σ V₁ V₂)
    (let loop ([V₁ : -V V₁] [V₂ : -V V₂] [seen : (℘ (Pairof -V -V)) ∅])
      (cond
        [(∋ seen (cons V₁ V₂)) #t]
        [else
         (match* (V₁ V₂)
           [((-b b₁) (-b b₂)) (not (equal? b₁ b₂))]
           [((-St 𝒾₁ αs₁) (-St 𝒾₂ αs₂))
            (or (not (equal? 𝒾₁ 𝒾₂))
                (for/or : Boolean ([α₁ : ⟪α⟫ αs₁] [α₂ : ⟪α⟫ αs₂])
                  (define Vs₁ (σ@ σ α₁))
                  (define Vs₂ (σ@ σ α₂))
                  (for/and : Boolean ([V₁ Vs₁])
                    (for/and : Boolean ([V₂ Vs₂])
                      (loop V₁ V₂ (set-add seen (cons V₁ V₂)))))))]
           [(_ _) #f])])))

  (: list-of-non-null-chars? : -σ -V → Boolean)
  ;; Check if a value is definitely a list of non-null characters
  (define (list-of-non-null-chars? σ V)
    (define-set seen : ⟪α⟫ #:eq? #t #:as-mutable-hash? #t)
    (with-debugging/off ((ans) (let go : Boolean ([V : -V V])
                                    (match V
                                      [(-b (list)) #t]
                                      [(-Cons αₕ αₜ)
                                       (and (for/and : Boolean ([Vₕ (σ@ σ αₕ)])
                                              (equal? '✗ (p∋Vs σ 'equal? (-b #\null) Vₕ)))
                                            (or
                                             (seen-has? αₜ)
                                             (begin
                                               (seen-add! αₜ)
                                               (for/and : Boolean ([Vₜ (σ@ σ αₜ)])
                                                 (go Vₜ)))))]
                                      [_ #f])))
      (printf "list-of-non-null-char? ~a -> ~a~n"
              (show-V V) ans)
      (for ([(α Vs) (span-σ (-σ-m σ) (V->⟪α⟫s V))])
        (printf "  - ~a ↦ ~a~n" (show-⟪α⟫ (cast α ⟪α⟫)) (set-map Vs show-V)))
      (printf "~n")))

  (: ts->bs : (Listof -?t) → (Option (Listof Base)))
  (define (ts->bs ts)
    (foldr (λ ([t : -?t] [?bs : (Option (Listof Base))])
             (and ?bs (-b? t) (cons (-b-unboxed t) ?bs)))
           '()
           ts))

  ;; Return an abstract value approximating all list element in `V`
  (define (extract-list-content [σ : -σ] [V : -St]) : (℘ -V)
    (define-set seen : ⟪α⟫ #:eq? #t #:as-mutable-hash? #t)
    (match-define (-Cons αₕ αₜ) V)
    (define Vs (σ@ σ αₕ))
    (let loop! ([αₜ : ⟪α⟫ αₜ])
      (unless (seen-has? αₜ)
        (seen-add! αₜ)
        (for ([Vₜ (σ@ σ αₜ)])
          (match Vₜ
            [(-Cons αₕ* αₜ*)
             (for ([Vₕ (σ@ σ αₕ*)])
               (set! Vs (Vs⊕ σ Vs Vₕ)))
             (loop! αₜ*)]
            [(-b (list)) (void)]
            [_ (set! Vs (Vs⊕ σ Vs (-● ∅)))]))))
    Vs)

  
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; Implication and Exclusion
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (define implication-table : (HashTable Symbol (℘ Symbol)) (make-hasheq))
  (define exclusion-table : (HashTable Symbol (℘ Symbol)) (make-hasheq))
  (define implication-table⁻¹ : (HashTable Symbol (℘ Symbol)) (make-hasheq))

  (: add-implication! : Symbol Symbol → Void)
  ;; Extend implication table and take care of transitivity
  (define (add-implication! p q)
    (unless (map-has? implication-table p q)
      (map-add! implication-table   p q #:eq? #t)
      (map-add! implication-table⁻¹ q p #:eq? #t)
      ;; implication is reflexive
      (add-implication! p p)
      (add-implication! q q)
      ;; implication is transitive
      (for ([q* (in-set (get-weakers q))])
        (add-implication! p q*))
      (for ([p₀ (in-set (get-strongers p))])
        (add-implication! p₀ q))
      ;; (r → ¬q) and (q₀ → q) implies r → ¬q₀
      (for* ([r (in-set (get-exclusions q))])
        (add-exclusion! p r))))

  (: add-exclusion! : Symbol Symbol → Void)
  ;; Extend exclusion table and take care of inferring existing implication
  (define (add-exclusion! p q)
    (unless (map-has? exclusion-table p q)
      (map-add! exclusion-table p q #:eq? #t)
      ;; (p → ¬q) and (q₀ → q) implies (p → ¬q₀)
      (for ([q₀ (in-set (get-strongers q))])
        (add-exclusion! p q₀))
      (for ([p₀ (in-set (get-strongers p))])
        (add-exclusion! p₀ q))
      ;; exclusion is symmetric
      (add-exclusion! q p)))

  (:* get-weakers get-strongers get-exclusions : Symbol → (℘ Symbol))
  (define (get-weakers    p) (hash-ref implication-table   p mk-∅eq))
  (define (get-strongers  p) (hash-ref implication-table⁻¹ p mk-∅eq))
  (define (get-exclusions p) (hash-ref exclusion-table     p mk-∅eq))

  (: o⇒o : Symbol Symbol → -R)
  (define (o⇒o p q)
    (cond [(eq? p q) '✓]
          [(∋ (get-weakers p) q) '✓]
          [(∋ (get-exclusions p) q) '✗]
          [else '?]))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; Range
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (define range-table : (HashTable Symbol Symbol) (make-hasheq))
  (define partial-prims : (HashTable Symbol Natural) (make-hasheq))

  (: set-range! : Symbol Symbol → Void)
  (define (set-range! o r) (hash-set-once! range-table o r))

  (: set-partial! : Symbol Natural → Void)
  (define (set-partial! o n) (hash-set! partial-prims o n))

  (: get-conservative-range : Symbol → Symbol)
  (define (get-conservative-range o) (hash-ref range-table o (λ () 'any/c)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; Arity
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (define arity-table : (HashTable Symbol Arity) (make-hasheq))

  (: update-arity! : Symbol Arity → Void)
  (define (update-arity! o a)
    (cond [(hash-ref arity-table o #f) =>
           (λ ([a₀ : Arity])
             (unless (arity-includes? a₀ a)
               (hash-set! arity-table o (normalize-arity (list a₀ a)))))]
          [else
           (hash-set! arity-table o a)]))

  (: prim-arity : Symbol → Arity)
  (define (prim-arity o) (hash-ref arity-table o (λ () (error 'get-arity "nothing for ~a" o))))
  )
