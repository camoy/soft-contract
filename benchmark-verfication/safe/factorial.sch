(module factorial racket
  (provide/contract
   [factorial (integer? . -> . integer?)])
  (define (factorial n)
    (if (zero? n) 1 (* n (factorial (sub1 n))))))

(require 'factorial)
(factorial •)
