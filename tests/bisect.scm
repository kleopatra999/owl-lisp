
(define (divide a b) (- (bisect (lambda (q) (> (* q b) a)) 0 a) 1))

(define (square n) (- (bisect (lambda (q) (> (* q q) n)) 0 n) 1))

(for-each
   (λ (limit)
      (lets
         ((rs (seed->rands (time-ms)))
          (rs n (rnd-range rs 3 (max limit 4)))
          (rs m (rnd-range rs n (* n 100000))))
         (if (= (sqrt n) (square n))
            (show " -> square ok " limit))
         (if (= (div n m) (divide n m))
            (show " -> divide ok " limit))))
   (map (λ (x) (expt 2 x)) (iota 3 1 100)))
