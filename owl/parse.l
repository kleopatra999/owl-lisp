;;;
;;; owl cfg parsing combinators and macros
;;;

,r "owl/unicode.l"
,r "owl/lazy.l"

(define-module lib-parse

   (import lib-lazy)
   (import lib-unicode) ; decoding code points in get-rune and runes->string

   ; (parser ll ok fail pos)
   ;      -> (ok ll' fail' val pos)
   ;      -> (fail fail-pos fail-msg')

   (export
      let-parses
      get-byte
      get-imm
      get-epsilon
      assert
      get-byte-if
      get-rune
      get-rune-if
      get-one-of
      get-word
      get-either
      get-any-of
      get-kleene*
      get-kleene+
      get-greedy*
      get-greedy+
      try-parse         ; parser x ll x path|False x errmsg|False x fail-val
      peek
      fd->exp-stream
      file->exp-stream
      null-stream?)

   (define (null-stream? ll)
      (cond
         ((null? ll) True)
         ((pair? ll) False)
         (else (null-stream? (ll)))))

   (define eof-error "end of input")

   (define (get-byte ll ok fail pos)
      (cond
         ((null? ll) (fail pos eof-error)) ; will always be the largest value 
         ((pair? ll) (ok (cdr ll) fail (car ll) (+ pos 1)))
         (else (get-byte (ll) ok fail pos))))

   ; read nothing, succeed with val
   (define (get-epsilon val)
      (λ (ll ok fail pos)
         (ok ll fail val pos)))

   ;; todo: in addition to assert would be useful to have compute (returns the value) and check <predicate> 
   (define (assert pred val) ; fixme: should have a error message to throw when no luck
      (λ (ll ok fail pos)
         (let ((res (pred val)))
            (if res
               (ok ll fail val pos)
               (fail pos "parser assert blocked")))))

   (define-syntax let-parses
      (syntax-rules (verify eval)
         ((let-parses 42 sc ft lst pos ((val (eval term)) . r) body)
            (let ((val term))
               (let-parses 42 sc ft lst pos r body)))
         ((let-parses 42 sc ft lst pos ((val parser) . r) body)
            (parser lst 
               (λ (lst ft val pos)
                  (let-parses 42 sc ft lst pos r body))
               ft pos))
         ((let-parses 42 sc ft lst pos () body) (sc lst ft body pos))
         ((let-parses 42 sc ft lst pos ((verify term msg) . r) body)
            (if term
               (let-parses 42 sc ft lst pos r body)
               (ft pos msg)))
         ((let-parses ((a . b) ...) body)
            (λ (ll ok fail pos)
               (let-parses 42 ok fail ll pos ((a . b) ...) body)))))

   ;; testing a slower one to check assertions
   (define (get-byte-if pred)
      (let-parses
         ((b get-byte)
          (verify (pred b) "bad byte")
          ;(_ (assert pred b))
          )
         b))

   (define peek-mark "loltron")
   (define (peek-val? x) (if (pair? x) (eq? (car x) peek-mark) False))

   ; make sure the next thing is *not* accepted by parser (unfortunate name, change later)
   (define (peek parser) ; fixme, add error message
      (λ (lst ok fail pos)
         (parser lst 
            (λ (lst fail val pos)
               ; we do *not* want a match
               (fail lst "peek matched"))
            (λ (fpos fmsg)
               ; ok not to match
               (ok lst fail 'peeked pos))
            pos)))

   (define (get-imm n)
      (let-parses
         ((a get-byte)
          (verify (eq? a n) '(expected n)))
         a))

   (define (get-one-of bytes)
      (get-byte-if (λ (x) (has? bytes x))))

   (define (get-word str val)
      (let ((bytes (string->bytes str)))
         (λ (lst ok fail pos)
            (let loop ((bytes bytes) (lst lst) (fail fail) (pos pos))
               (if (null? bytes)
                  (ok lst fail val pos)
                  (get-byte lst
                     (λ (lst fail byte pos)
                        (if (eq? byte (car bytes))
                           (loop (cdr bytes) lst fail pos)
                           (fail pos (list "expected next '" (runes->string bytes) "'"))))
                     fail pos))))))

   (define (get-either a b)
      (λ (lst ok fail pos)
         (a lst ok
            (λ (fa fai)
               (b lst ok (λ (fb fbi) (if (< fa fb) (fail fb fbi) (fail fa fai))) pos))
            pos)))

   (define (get-kleene* par)
      (get-either
         (let-parses
            ((hd par) (tl (get-kleene* par)))
            (cons hd tl))
         (get-epsilon null)))

   ; get all of successful parses of parser not allowing backtracking
   ; intention being that "aaaaa" has quite a few combinations of (kleene+ a), 
   ; and when describing something like lexical structure, which is usually 
   ; handled by a pass greedily matching regular expressions, this may cause 
   ; unexpected exponential slowdowns on parse errors when using simple 
   ; parsing combinators like these in lib-parse.

   (define (get-greedy parser zero-ok?)
      (λ (lst ok fail pos)
         (let loop ((lst lst) (rvals null) (pos pos))
            (parser lst
               (λ (lst fail val pos)
                  (loop lst (cons val rvals) pos))
               (λ (fpos freason)
                  (if (or zero-ok? (pair? rvals))
                     (ok lst fail (reverse rvals) pos) ; pass the original failure cont
                     (fail fpos freason))) ; could fail differently when zero and requested at least one
               pos))))

   (define (get-greedy* parser) (get-greedy parser True))
   (define (get-greedy+ parser) (get-greedy parser False))

   (define (get-kleene+ what)
      (let-parses
         ((hd what)
          (tl (get-kleene* what)))
         (cons hd tl)))

   (define-syntax get-any-of
      (syntax-rules ()
         ((get-any-of a) a)
         ((get-any-of a b) (get-either a b))
         ((get-any-of a . bs)
            (get-either a (get-any-of . bs)))))

   (define (get-between below above)
      (get-byte-if
         (λ (x)
            (and (lesser? below x) (lesser? x above)))))

   ; #b10xxxxxx
   (define get-extension-byte 
      (let-parses
         ((b get-byte)
          (verify (eq? #b10000000 (fxband b #b11000000)) "Bad extension byte"))
         b))

   (define get-rune
      (get-any-of
         (get-byte-if (λ (x) (lesser? x 128)))
         (let-parses
            ((a (get-between 127 224))
             (verify (not (eq? a #b11000000)) "blank leading 2-byte char") ;; would be non-minimal
             (b get-extension-byte))
            (two-byte-point a b))
         (let-parses
            ((a (get-between 223 240))
             (verify (not (eq? a #b11100000)) "blank leading 3-byte char") ;; would be non-minimal
             (b get-extension-byte) (c get-extension-byte))
            (three-byte-point a b c))
         (let-parses
            ((a (get-between 239 280))
             (verify (not (eq? a #b11110000)) "blank leading 4-byte char") ;; would be non-minimal
             (b get-extension-byte) (c get-extension-byte) (d get-extension-byte))
            (four-byte-point a b c d))))

   (define (get-rune-if pred)
      (let-parses
         ((rune get-rune)
          (rune (assert pred rune)))
         rune))


   ;;;
   ;;; Port data streaming and parsing
   ;;;

   ; this is fairly distinct from the rest of lib-parse, because it mainly deals with 
   ; IO operation sequencing.

   ; notice that this difficulty comes from owl not havign side-effects on data structures
   ; even in the VM level, ruling out lazy lists and and manually mutated streams, which 
   ; are usually used in functional parsers.

   (define (stdio-port? port)
      (has? (list stdin stdout stderr) port))

   ; rchunks fd block? -> rchunks' end?
   ;; bug: maybe-get-input should now use in-process mail queuing using return-mails syscall at the end if necessary 
   (define (maybe-get-input rchunks fd block? prompt)
      ;(if (and block? prompt)
      ;   (begin (display prompt) (flush-port stdout)))
      (let ((env ((if block? wait-mail check-mail)))) ; read a response in case one comes
         (if env
            ;; handle received input
            (lets ((sender chunk env))
               (if (eq? sender fd) ; check that the mail is indeed from the port
                  (cond
                     ((not chunk)
                        ; read error in port
                        (show "fd->exp-stream: stopping reading after read error at port " fd)
                        (values rchunks True))
                     ((eof? chunk)
                        ; normal end if input, no need to call me again
                        (if (not (stdio-port? fd))
                           (close-port fd))
                        (values rchunks True))
                     (else
                        ; a chunk of data was received
                        (mail fd 'input) ; request more of it when available
                        (wait 1)
                        ; read it if available
                        (maybe-get-input (cons chunk rchunks) fd False prompt)))
                  (begin
                     (show " *** ERROR ERROR ERROR parser thread got mail from non-hoped-fd thread: " sender)
                     (! 10000)
                     (maybe-get-input rchunks fd block? prompt))))
            (values rchunks False))))

   (define (push-chunks data rchunks)
      (if (null? rchunks)
         data
         (append data
            (foldr append null
               (map vec->list (reverse rchunks))))))

   ;; todo: fd->exp-stream could easily keep track of file name and line number to show also those in syntax error messages

   ; -> lazy list of parser results, possibly ending to ... (fail <pos> <info> <lst>)

   (define (fd->exp-stream fd prompt parse fail re-entry?)
      ; request for more input unless this is a re-generated stream after a previous syntax error etc
      ; in which case there already is an input request pending. 
      (if (not re-entry?)
         (mail fd 'input)) ; always keep one input reading request going to the fd
      (wait 1)
      ; finished means a request for more data is pending, and it makes sense to wait for a response
      (let loop ((old-data null) (block? True) (finished? False)) ; old-data not successfullt parseable (apart from epsilon)
         (lets 
            ((rchunks end? 
               (if finished? 
                  (values null True) 
                  (maybe-get-input null fd (or (null? old-data) block?) 
                     (if (null? old-data) prompt "|   "))))
             (data (push-chunks old-data rchunks)))
            (if (null? data)
               (if end? null (loop data True False))
               (parse data
                  (λ (data-tail backtrack val pos)
                     (pair val 
                        (if (and finished? (null? data-tail))
                           null
                           (loop data-tail (null? data-tail) end?))))
                  (λ (pos info)
                     (cond
                        (end?
                           ; parse failed and out of data -> must be a parse error, like unterminated string
                           (list (fail pos info data)))
                        ((= pos (length data))
                           ; parse error at eof and not all read -> get more data
                           (loop data True end?))
                        (else
                           ; better leave port closing to those who also open them
                           ;(close-port fd) ; wouldn't want to close port 0 on syntax errors.
                           (list (fail pos info data)))))
                  0)))))


; (parser ll ok fail pos)
;      -> (ok ll' fail' val pos)
;      -> (fail fail-pos fail-msg')

   (define (file->exp-stream path prompt parse fail)
      (let ((fd (open-input-file path)))
         (if fd
            (fd->exp-stream fd prompt parse fail False)
            False)))

   (define (print-syntax-error reason bytes posn)
      (print reason)
      (mail stdout '(32 32 32)) ; indent by 3 spaces
      (mail stdout (cons 96 (append (force bytes) '(39 10))))
      (mail stdout (map (λ (x) 32) (iota 0 1 (+ posn 4)))) ; move to right position
      (mail stdout '(94 10)))

   ; find the row where the error occurs
   ; keep the row number stored so it can be shown in output
   (define (print-row-syntax-error path reason bytes err-posn)
      (let row-loop ((row 1) (bytes bytes) (pos 0) (rthis null))
         (cond
            ((null? bytes)
               (for-each display (list path ":" row " "))
               (print-syntax-error reason (reverse rthis) (- pos err-posn)))
            ((not (pair? bytes)) ; force
               (row-loop row (bytes) pos rthis))
            ((= (car bytes) 10)
               (if (> err-posn pos)
                  (row-loop (+ row 1) (cdr bytes) (+ pos 1) null)
                  (begin
                     (for-each display (list path ":" row " "))
                     (print-syntax-error reason (reverse rthis) (- (length rthis) (+ 1 (- pos err-posn)))))))
            (else
               (row-loop row (cdr bytes) (+ pos 1) (cons (car bytes) rthis))))))

   (define (has-newline? ll)   
      (cond
         ((null? ll) False)
         ((not (pair? ll)) (has-newline? (ll)))
         ((eq? (car ll) 10) True)
         (else (has-newline? (cdr ll)))))

   ; can be unforced
   (define (null-ll? ll)
      (cond
         ((null? ll) True)
         ((pair? ll) False)
         (else (null-ll? (ll)))))

   ; try to parse all of data with given parser, or return fail-val
   ; printing a nice error message if maybe-error-msg is given 

   (define (try-parse parser data maybe-path maybe-error-msg fail-val)
      (parser data    
         (lambda (data fail val pos)
            (if (null-ll? data)
               ; all successfully parsed
               val
               ; something unparsed. backtrack.
               (fail pos "out of data")))
         (lambda (pos reason)
            ; print error if maybe-error-msg is given
            (if maybe-error-msg
               (if (or maybe-path (has-newline? data))
                  (print-row-syntax-error 
                     (or maybe-path "input") 
                     maybe-error-msg data pos)
                  (print-syntax-error maybe-error-msg data (- pos 1)))) ; is the one from preceding newlines?
            fail-val)
         0))
)


(import lib-parse)

(define test-parser
   (let-parses
      ((hd (get-kleene* (get-imm 97)))
       (tl (get-imm 98)))
      (cons hd tl)))

;(try-parse 
;   (let-parses
;      ((as (get-kleene* (get-imm 97)))
;       (ab (get-word "ab" 'ab)))
;      (cons as ab))
;   (str-iter "aaaabaaa")
;   False "trololo" 'failed)

;(try-parse
;   (let-parses
;      ((a get-byte)
;       (b get-byte)
;       (sum (eval (+ a b)))
;       (c (get-imm sum)))
;      (list a b c))
;   '(1 2 3)
;   False "trololo" 'failed)
