#lang racket

(define (list-add1 ns)
  (list (+ (car ns) 1)))

(define Integer exact-integer?)
(define Listof listof)

(provide
  (contract-out [list-add1 (-> (and/c (Listof Integer) cons?) (Listof Integer))]))
