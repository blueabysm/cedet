;;; wisent.el --- GNU Bison for Emacs - Runtime

;; Copyright (C) 2002, 2003 David Ponce

;; Author: David Ponce <david@dponce.com>
;; Maintainer: David Ponce <david@dponce.com>
;; Created: 30 Janvier 2002
;; Keywords: syntax
;; X-RCS: $Id: wisent.el,v 1.28 2003-06-29 12:48:42 ponced Exp $

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2, or (at
;; your option) any later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:
;;
;; Parser engine and runtime of Wisent.
;;
;; Wisent (the European Bison ;-) is an Elisp implementation of the
;; GNU Compiler Compiler Bison.  The Elisp code is a port of the C
;; code of GNU Bison 1.28 & 1.31.
;;
;; For more details on the basic concepts for understanding Wisent,
;; read the Bison manual ;)
;;
;; For more details on Wisent itself read the Wisent manual.

;;; History:
;;

;;; Code:
(provide 'wisent)

(defgroup wisent nil
  "
           /\\_.-^^^-._/\\     The GNU
           \\_         _/
            (     `o  `      (European ;-) Bison
             \\      ` /
             (   D  ,�       for Emacs!
              ` ~ ,�
               `\"\""
  :group 'semantic)

;;;; ----------------
;;;; Common constants
;;;; ----------------

;; Special terminal symbols
(defconst wisent-eoi-term '$EOI
  "End Of Input token.")

(defconst wisent-error-term 'error
  "Error recovery token.")

;; Special parser action tags
(defconst wisent-accept-tag 'accept
  "Accept result after input successfully parsed.")

(defconst wisent-error-tag 'error
  "Process a syntax error.")

;;;; --------------
;;;; Runtime stuff.
;;;; --------------

(defun wisent-automaton-p (obj)
  "Return non-nil if OBJ is a LALR automaton.
If OBJ is a symbol check its value."
  (and obj (symbolp obj) (boundp obj)
       (setq obj (symbol-value obj)))
  (and (vectorp obj) (= 4 (length obj))
       (vectorp (aref obj 0)) (vectorp (aref obj 1))
       (= (length (aref obj 0)) (length (aref obj 1)))
       (listp (aref obj 2)) (vectorp (aref obj 3))))

;;;; --------------------
;;;; The LR parser engine
;;;; --------------------

(defcustom wisent-parse-max-stack-size 500
  "*The parser stack size."
  :type 'integer
  :group 'wisent)

(defcustom wisent-parse-max-recover 3
  "*Number of tokens to shift before turning off error status."
  :type 'integer
  :group 'wisent)

(defvar wisent-discarding-token-functions nil
  "List of functions to be called when discarding a lexical token.
These functions receive the lexical token discarded.
When the parser encounters unexpected tokens, it can discards them,
based on what directed by error recovery rules.  Either when the
parser reads tokens until one is found that can be shifted, or when an
semantic action calls the function `wisent-skip-token' or
`wisent-skip-block'.
For language specific hooks, make sure you define this as a local
hook.")

(defvar wisent-nerrs nil
  "The number of parse errors encountered so far.")

(defvar wisent-lookahead nil
  "The lookahead lexical token.
This value is non-nil if the parser terminated because of an
unrecoverable error.")

;;;; Internal stuff

;; The current parser action.  Stop parsing when set to nil.
(defvar wisent-loop nil)

;;;; Variables and macros that are useful in grammar actions.

(defvar wisent-parse-lexer-function nil
  "The user supplied lexer function.
This function don't have arguments.  The actual value of this variable
is local to the parser.")

(defvar wisent-parse-error-function nil
  "The user supplied error function.
This function must accept one argument, a message string.  The actual
value of this variable is local to the parser.")

(defvar wisent-input nil
  "The last token read.
The actual value of this variable is local to the parser.")

(defvar wisent-recovering nil
  "Non nil when the parser is recovering.
The actual value of this variable is local to the parser.")

(defvar $region nil
  "Unused global definition to avoid compiler warnings.
The actual value of this variable is local to each semantic action.")

(defvar $nterm nil
  "Unused global definition to avoid compiler warnings.
The actual value of this variable is local to each semantic action.")

(defmacro wisent-lexer ()
  "Obtain the next terminal in input."
  '(funcall wisent-parse-lexer-function))

(defmacro wisent-error (msg)
  "Call the user supplied error reporting function with messsage MSG."
  `(funcall wisent-parse-error-function ,msg))

(defmacro wisent-errok ()
  "Resume generating error messages immediately for subsequent syntax errors.
This is useful primarily in error rules."
  '(setq wisent-recovering nil))

(defmacro wisent-clearin ()
  "Discard the current look-ahead token.
This will cause a new token to be read.
This is useful primarily in error rules."
  '(setq wisent-input nil))

(defmacro wisent-abort ()
  "Abort parsing and save the look-ahead token.
This is useful primarily in error rules."
  '(setq wisent-lookahead wisent-input
         wisent-loop nil))

(defmacro wisent-set-region (start end)
  "Change the region of text matched by the current nonterminal.
START and END are respectively the beginning and end positions of the
region.  If START or END values are not a valid positions the region
is set to nil."
  `(setq $region (and (number-or-marker-p ,start)
                      (number-or-marker-p ,end)
                      (cons ,start ,end))))

(defsubst wisent-skip-token ()
  "Skip an invalid token and try to continue parsing.
To be used in grammar recovery actions."
  (wisent-error (format "Skipping invalid '%s'" $nterm))
  ;; Clear the lookahead token
  (if (eq (car wisent-input) wisent-eoi-term)
      ;; does nothing at EOI to avoid infinite recovery loop
      nil
    (run-hook-with-args
     'wisent-discarding-token-functions wisent-input)
    (wisent-clearin)
    (wisent-errok)))

(defun wisent-skip-block ()
  "Safely skip a parenthesized block and try to continue parsing.
To be used in grammar recovery actions."
  (let ((start (car $region))
        end input block)
    (if (not (number-or-marker-p start))
        ;; No nonterminal region available, skip
        ;; token and try to continue?
        (wisent-skip-token)

      ;; Try to skip a block
      (if (not (setq end (save-excursion
                           (goto-char start)
                           (and (looking-at "\\s(")
                                (condition-case nil
                                    (1- (scan-lists (point) 1 0))
                                  (error nil))))))
          ;; Not actually a block, skip token and try to continue?
          (wisent-skip-token)
        
        ;; Ok to safely skip the block
        (wisent-error (format "Skipping invalid '%s' from %s to %s"
                              $nterm start end))
        ;; read input until matching close paren or EOI
        (setq input wisent-input)
        (while (and (not (eq (car input) wisent-eoi-term))
                    (< (nth 2 input) end))
          (run-hook-with-args
           'wisent-discarding-token-functions input)
          (setq input (wisent-lexer)))
        ;; Clear the lookahead token
        (if (eq (car wisent-input) wisent-eoi-term)
            ;; does nothing at EOI to avoid infinite recovery loop
            nil
          (wisent-clearin)
          (wisent-errok))
        ;; Return a nil value with adjusted start/end positions
        (cons nil (wisent-set-region start (1+ end)))))))

;;;; Other parser stuff

(defsubst wisent-region (&rest positions)
  "Return the start/end positions of the region including POSITIONS.
Each element of POSITIONS is a pair (START-POS . END-POS) or nil.  The
returned value is the pair (MIN-START-POS . MAX-END-POS) or nil if no
POSITIONS are available."
  (let ((pl (delq nil positions)))
    (if pl
        (cons (apply #'min (mapcar #'car pl))
              (apply #'max (mapcar #'cdr pl))))))

(defmacro wisent-parse-action (i al)
  "Return the next parser action.
I is a token item number and AL is the list of (item . action)
availables at current state.  The first element of AL contains the
default action for this state."
  `(cdr (or (assq ,i ,al) (car ,al))))

(defsubst wisent-parse-start (start starts)
  "Return the first lexical token to shift for START symbol.
STARTS is the table of allowed start symbols or nil if the LALR
automaton has only one entry point."
  (if (null starts)
      ;; Only one entry point, return the first lexical token
      ;; available in input.
      (wisent-lexer)
    ;; Multiple start symbols defined, return the internal lexical
    ;; token associated to START.  By default START is the first
    ;; nonterminal defined in STARTS.
    (let ((token (cdr (if start (assq start starts) (car starts)))))
      (if token
          (list token (symbol-name token))
        (error "Invalid start symbol %s" start)))))

(defvar wisent-pre-parse-hook nil
  "Normal hook run just before entering the LR parser engine.")

(defvar wisent-post-parse-hook nil
  "Normal hook run just after the LR parser engine terminated.")

(defun wisent-parse (automaton lexer &optional error start)
  "Parse input using the automaton specified in AUTOMATON.

- AUTOMATON is an LALR(1) automaton generated by
  `wisent-compile-grammar'.

- LEXER is a function with no argument called by the parser to obtain
  the next terminal (token) in input.

- ERROR is an optional reporting function called when a parse error
  occurs.  It receives a message string to report.  It defaults to the
  function `error'.

- START specify the start symbol (nonterminal) used by the parser as
  its goal.  It defaults to the start symbol defined in the grammar
  \(see also `wisent-compile-grammar')."
  (run-hooks 'wisent-pre-parse-hook)
  (let* ((actions (aref automaton 0))
         (gotos   (aref automaton 1))
         (starts  (aref automaton 2))
         (stack (make-vector wisent-parse-max-stack-size nil))
         (sp 0)
         (wisent-loop t)
         (wisent-parse-error-function (or error #'error))
         (wisent-parse-lexer-function lexer)
         (wisent-recovering nil)
         (wisent-input (wisent-parse-start start starts))
         state tokid choices choice)
    (setq wisent-nerrs     0 ;; Reset parse error counter
          wisent-lookahead nil) ;; and lookahead token
    (aset stack 0 0) ;; Initial state
    (while wisent-loop
      (setq state (aref stack sp)
            tokid (car wisent-input)
            wisent-loop (wisent-parse-action tokid (aref actions state)))
      (cond
       
       ;; Input succesfully parsed
       ;; ------------------------
       ((eq wisent-loop wisent-accept-tag)
        (setq wisent-loop nil))
       
       ;; Syntax error in input
       ;; ---------------------
       ((eq wisent-loop wisent-error-tag)
        ;; Report this error if not already recovering from an error.
        (or wisent-recovering
            (wisent-error
             (format "Parse error - unexpected token %s(%S)%s"
                     tokid
                     (cadr wisent-input)
                     (if (cddr wisent-input)
                         (format " at %s" (cddr wisent-input))
                       ""))))
        ;; Increment the error counter
        (setq wisent-nerrs (1+ wisent-nerrs))
        ;; If just tried and failed to reuse lookahead token after an
        ;; error, discard it.
        (if (eq wisent-recovering wisent-parse-max-recover)
            (if (eq tokid wisent-eoi-term)
                (setq wisent-loop nil) ;; Terminate if at end of input.
              (run-hook-with-args
               'wisent-discarding-token-functions wisent-input)
              (setq wisent-input (wisent-lexer)))
          
          ;; Else will try to reuse lookahead token after shifting the
          ;; error token.
          
          ;; Each real token shifted decrements this.
          (setq wisent-recovering wisent-parse-max-recover)
          ;; Pop the value/state stack to see if an action associated
          ;; to special terminal symbol 'error exists.
          (setq choices (aref actions state))
          (while (and (>= sp 0)
                      (not (and (setq state   (aref stack sp)
                                      choices (aref actions state)
                                      choice  (assq wisent-error-term choices))
                                (natnump (cdr choice)))))
            (setq sp (- sp 2)))
          
          (if (not choice)
              ;; No 'error terminal was found.  Just terminate.
              (wisent-abort)
            
            ;; Try to recover and continue parsing.
            ;; Shift the error terminal.
            (setq state (cdr choice)    ; new state
                  sp    (+ sp 2))
            (aset stack (1- sp) nil)    ; push value
            (aset stack sp state)       ; push new state
            ;; Try to adjust input to error recovery state.
            (setq choices (aref actions state))
            ;; If 'error is followed by an action continue parsing
            ;; (that is do the action).  Otherwise read until the
            ;; input token matches the terminal symbol following
            ;; 'error or EOI is reached.
            (if (cdr choices)
                (while
                    (progn
                      (or wisent-input
                          (setq wisent-input (wisent-lexer)
                                choice (car wisent-input)))
                      (not (or (eq wisent-eoi-term choice)
                               (assq choice choices))))
                  (run-hook-with-args
                   'wisent-discarding-token-functions wisent-input)
                  (setq wisent-input nil))))))
       
       ;; Shift current token on top of the stack
       ;; ---------------------------------------
       ((natnump wisent-loop)
        ;; Count tokens shifted since error; after
        ;; `wisent-parse-max-recover', turn off error status.
        (setq wisent-recovering (and (natnump wisent-recovering)
                                     (> wisent-recovering 1)
                                     (1- wisent-recovering)))
        (setq sp (+ sp 2))
        (aset stack (1- sp) (cdr wisent-input))
        (aset stack sp wisent-loop)
        (setq wisent-input (wisent-lexer)))
       
       ;; Reduce by rule (call semantic action)
       ;; -------------------------------------
       (t
        (setq sp (funcall wisent-loop stack sp gotos))
        (or wisent-input (setq wisent-input (wisent-lexer))))))
    (run-hooks 'wisent-post-parse-hook)
    (car (aref stack 1))))

;;; wisent.el ends here
