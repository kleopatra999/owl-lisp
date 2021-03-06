; tags: 
(define x True)
(define o False)

(define zero '())

(define one (cons x zero))

(define (succ n)
	(cond	
		((null? n) 
			(cons x n))
		((car n)
			(cons o
				(succ (cdr n))))
		(else
			(cons x (cdr n)))))

(define (pred n)
	(if (car n)
		(let ((rest (cdr n)))
			(if (null? rest)
				rest
				(cons o rest)))
		(cons x
			(pred (cdr n)))))

(define (add a b)
	(if (null? b)
		a
		(add (succ a) (pred b))))

(define (sub a b)
	(if (null? b)
		a
		(sub (pred a) (pred b))))

(define (multiplier a b n)
	(if (null? b)
		n
		(multiplier a (pred b) (add n a))))

(define (mult a b)
	(multiplier a b zero))

(define (same? a b)
	(cond
		((null? a) (null? b))
		((car a)
			(if (car b) 
				(same? (cdr a) (cdr b))
				False))
		(else
			(if (car b)
				False
				(same? (cdr a) (cdr b))))))

(define big (list o o o o o o x x))

(define (show-digits n)
	(if (pair? n)
		(begin
			(if (car n)
				(display "x ")
				(display "o "))
			(show-digits (cdr n)))
		'blank))

(define (show-number n)
	(if (null? n)
		(display "o")
		(show-digits n))
	(display "
"))

(define (test n)
	;(display " -> ") (show-number n)
	(cond
		((same? n big) (cons 42 null))
		((not (same? (pred (succ n)) n)) False)
		((not (same? (add big n) (add n big))) False)
		((not (same? (add (mult n n) n) (mult n (succ n)))) False)
		((not (same? (sub n n) zero)) False)
		((not (same? (sub (succ n) n) one)) False)
		((not (same? (mult n (succ one)) (add n n))) False)
		((not (same? (add n (add n n)) (add (add n n) n))) False)
		((not (same? (add n (mult one n)) (add (mult n one) n))) False)
		(else (test (succ n)))))

test

