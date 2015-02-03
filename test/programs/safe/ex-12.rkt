#lang racket
(require soft-contract/fake-contract)

(define (carnum? p) (number? (car p)))

(provide/contract
 [carnum? (->i ([p cons?]) (res (p) (and/c boolean? (λ (a) (equal? a (number? (car p)))))))])
