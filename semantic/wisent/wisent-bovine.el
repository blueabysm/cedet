;;; wisent-bovine.el --- Wisent - Semantic gateway

;; Copyright (C) 2001, 2002 David Ponce

;; Author: David Ponce <david@dponce.com>
;; Maintainer: David Ponce <david@dponce.com>
;; Created: 30 Aug 2001
;; Keywords: syntax
;; X-RCS: $Id: wisent-bovine.el,v 1.21 2002-08-11 09:39:45 ponced Exp $

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
;; Here are functions necessary to use the Wisent LALR parser from
;; Semantic environment.

;;; History:
;; 

;;; Code:

(require 'semantic)
(require 'wisent)

;;; Lexical analysis
;;

(defvar wisent-lex-istream nil
  "Input stream of `semantic-lex' syntactic tokens.")

(defvar wisent-lex-tokens-obarray nil
  "Buffer local token obarray.")
(make-variable-buffer-local 'wisent-lex-tokens-obarray)

(defvar wisent-lex-lookahead nil
  "Extra lookahead token.
When non-nil it is directly returned by `wisent-lex-function'.")

(defsubst wisent-lex-token-rules (token)
  "Return matching rules of TOKEN."
  (symbol-value
   (intern-soft (symbol-name token) wisent-lex-tokens-obarray)))

(defsubst wisent-lex-token-get (token property)
  "For token TOKEN, get the value of PROPERTY."
  (get (intern-soft (symbol-name token) wisent-lex-tokens-obarray)
       property))

(defun wisent-lex-add-token (token obarray)
  "Check and add TOKEN to OBARRAY."
  (let* ((stok  (intern (car token) obarray))
         (rules (cdr token))
         rule entry entries default)
    (while rules
      (setq rule  (car rules)
            rules (cdr rules))
      (if (cdr rule)
          (setq entries (cons rule entries))
        (setq rule (car rule))
        (if default
            (message "*** `%s' default rule %S redefined as %S"
                     stok default rule))
        (setq default rule)))
    ;; Ensure that the default rule is the first one.
    (set stok (cons default (nreverse entries)))))

(defsubst wisent-lex-put-default (name property value obarray)
  "Set NAME's PROPERTY to VALUE.
Define NAME in OBARRAY if it does not already exist."
  (let ((symbol (intern-soft name obarray)))
    (or symbol (set (setq symbol (intern name obarray)) nil))
    (put symbol property value)))

(defun wisent-lex-make-token-table (tokens &optional propertyalist)
  "Convert a list of TOKENS into an obarray and return it.
If optional argument PROPERTYALIST is non nil, then interpret it, and
apply those properties"
  ;; Create the symbol hash table
  (let* ((obarray (make-vector 13 0))
         property)
    ;; fill it with stuff
    (while tokens
      (wisent-lex-add-token (car tokens) obarray)
      (setq tokens (cdr tokens)))
    ;; Set up some useful default properties
    (wisent-lex-put-default "punctuation" 'char-literal t obarray)
    (wisent-lex-put-default "open-paren"  'char-literal t obarray)
    (wisent-lex-put-default "close-paren" 'char-literal t obarray)
    ;; Apply all properties
    (while propertyalist
      (setq property      (car propertyalist)
            propertyalist (cdr propertyalist))
      (put (or (intern-soft (car property) obarray)
               (signal 'wrong-type-argument
                       (list (car property) 'token)))
           (nth 1 property)
           (nth 2 property)))
    obarray))

(defsubst wisent-lex-match (text default rules &optional usequal)
  "Return lexical symbol matching TEXT or DEFAULT if not found.
RULES is an alist of (TOKEN . MATCHER).  If optional argument USEQUAL
is non-nil use direct string comparison between TEXT and MATCHERs
instead of regexp match."
  (if usequal
      (or (car (rassoc text rules)) default)
    (let* (lexem regex)
      (while (and (not lexem) rules)
        (if (or (null (setq regex (cdar rules)))
                (string-match regex text))
            (setq lexem (caar rules))
          (setq rules (cdr rules))))
      (or lexem default))))

;;; Semantic 2.x lexical analysis
;;

;; Some general purpose analyzers
;;
(define-lex-regex-analyzer wisent-lex-punctuation
  "Detect and create punctuation tokens."
  "\\(\\s.\\|\\s$\\|\\s'\\)+"
  (let* ((punct (match-string 0))
         (start (match-beginning 0))
         (rules (cdr (wisent-lex-token-rules 'punctuation)))
         entry)
    ;; Starting with the longest punctuation string, search if it
    ;; matches a punctuation of this language.
    (while (and (> (length punct) 0)
                (not (setq entry (rassoc punct rules))))
      (setq punct (substring punct 0 -1)))
    (semantic-lex-token (car entry) start (+ start (length punct)))))

;;; Lexer creation macros
;;
(defmacro wisent-lex-eoi ()
  "Return an End-Of-Input lexical token.
The EOI token is like this: ($EOI "" POINT-MAX . POINT-MAX)."
  `(cons ',wisent-eoi-term
         (cons ""
               (cons (point-max) (point-max)))))

(defmacro define-wisent-lexer (name doc &rest body)
  "Create a new lexical analyzer with NAME.
DOC is a documentation string describing this analyzer.
When a token is available in `wisent-lex-istream', eval BODY forms
sequentially.  BODY must return a lexical token for the LALR parser.

Each token in input was produced by `semantic-lex', it is a list:

  (TOKSYM START . END)

TOKSYM is a terminal symbol used in the grammar.
START and END mark boundary in the current buffer of that token's
value.

Returned tokens must have the form:

  (TOKSYM VALUE START . END)

where VALUE is the buffer substring between START and END positions."
  `(defun
     ,name () ,doc
     (cond
      (wisent-lex-lookahead
       (prog1 wisent-lex-lookahead
         (setq wisent-lex-lookahead nil)))
      (wisent-lex-istream
       ,@body)
      ((wisent-lex-eoi)))))

;;; General purpose lexers
;;

(define-wisent-lexer wisent-flex
  "Return the next available lexical token in Wisent's form.
Eat syntactic tokens produced by `semantic-lex', available in
variable `wisent-lex-istream', and return Wisent's lexical tokens.
See documentation of `semantic-lex-tokens' for details on the
syntactic tokens returned by `semantic-lex'.

In most cases one syntactic token is mapped to one lexical token.  But
in certain cases several successive syntactic tokens can be mapped to
one lexical tokens.  A common case is given by arithmetic operators
which can be made of multiple punctuations.

Also the mapping between syntactic tokens and lexical ones uses regexp
match by default, but can use string comparison too.

The rules specifying how to do the mapping are defined in two symbol
tables:

  - The keyword table in variable `semantic-lex-keywords-obarray';

  - The token table in variable `wisent-lex-tokens-obarray'.

Keywords are directly mapped to equivalent Wisent's lexical tokens
like this (SL- prefix means `semantic-lex', WL- `wisent-lex'):

  (SL-KEYWORD start . end)  ->  (WL-KEYWORD \"name\" start . end)

Mapping of other tokens obeys to rules in the token table.  Here is an
example on how to define the mapping of 'punctuation syntactic tokens.

1. Add (`intern') the symbol 'punctuation into the token table.

2. Set its value to the mapping rules to use.  Mapping rules are an
   alist of (WL-TOKEN . MATCHER) elements.  WL-TOKEN is the category
   of the Wisent's lexical token (for example 'OPERATOR).  MATCHER is
   the regular expression used to filter input data (for example
   \"[+-]\").  The first element of the mapping rule alist defines a
   default matching rule. It must be nil or have the form (WL-TOKEN).
   When there is no mapping rule that matches the syntactic token
   value, the default WL-TOKEN or nil is returned.

   Thus, if the syntactic token symbol 'punctuation has the mapping
   rules '(nil (OPERATOR . \"[+-]\")), the following token:

   (punctuation 1 . 2)

   will be mapped to the lexical token

   (OPERATOR \"+\" 1 . 2)

   if the buffer contained \"+\" between positions 1 and 2.

   To define multiple matchers for the same WL-TOKEN just give
   several (WL-TOKEN . MATCHER) values.  MATCHERs will be tried in
   sequence until one matches.

3. Optionally customize how `wisent-flex' will interpret mapping
   rules, using symbol properties.

   The following properties are recognized:

   'string
     If non-nil MATCHERs are interpreted as strings instead of
     regexps, and matching uses direct string comparison.  This could
     speed up things in certain cases.

   'multiple
     non-nil indicates to lookup at multiple successive syntactic
     tokens and try to match the longest one.

   'char-literal
     non-nil indicates to return the first character of the syntactic
     token value as the lexical token category.  It is the default for
     punctuation, open-paren and close-paren syntactic tokens.  Use
     this property when grammar contains references to character
     literals.

   'handler
     If non-nil must specify a function with no argument that will be
     called first to map the syntactic token.  It must return a
     lexical token or nil, and update the input stream in variable
     `wisent-lex-istream' accordingly.

   The following example maps multiple punctuations to operators and
   use string comparison:

   (let ((entry (intern 'punctuation token-table)))
     (set entry '(nil ;; No default mapping
                  (LSHIFT . \"<<\") (RSHIFT . \">>\")
                  (LT     .  \"<\") (GT     .  \">\")))
     (put entry 'string   t)
     (put entry 'multiple t))"
  (let* ((is   wisent-lex-istream)
         (flex (car is))
         (stok (semantic-lex-token-class flex))
         (text (semantic-lex-token-text flex))
         default rules usequal wlex term beg end ends n is2)
      
    (if (setq term (semantic-lex-keyword-p text))
       
        ;; Keyword
        ;; -------
        (setq wlex (cons term
                         (cons text
                               (semantic-lex-token-bounds flex)))
              ;; Eat input stream
              wisent-lex-istream (cdr is))
                
        
      ;; Token
      ;; -----
      (if (null (setq rules (wisent-lex-token-rules stok)))
          ;; Eat input stream
          (setq wisent-lex-istream (cdr is))
          
        ;; Map syntactic token following RULES
        (setq default (car rules)
              rules   (cdr rules))
        (cond
           
         ;; If specified try a function first to map token.
         ;; It must return a lexical token or nil and update the
         ;; input stream (`wisent-lex-istream') accordingly.
         ((and (setq n (wisent-lex-token-get stok 'handler))
               (setq wlex (funcall n))))
           
         ;; Several/One mapping
         ((wisent-lex-token-get stok 'multiple)
          (setq beg  (semantic-lex-token-start flex)
                end  (semantic-lex-token-end   flex)
                ends (list end)
                n    1
                is2  (cdr is)
                flex (car is2))
          ;; Collect successive `semantic-lex' tokens
          (while (and (eq (semantic-lex-token-class flex) stok)
                      (= end (semantic-lex-token-start flex)))
            (setq end  (semantic-lex-token-end flex)
                  ends (cons end ends)
                  n    (1+ n)
                  is2  (cdr is2)
                  flex (car is2)))
          ;; Search the longest match
          (setq usequal (wisent-lex-token-get stok 'string))
          (while (and (not wlex) ends)
            (setq end  (car ends)
                  text (buffer-substring-no-properties beg end)
                  term (wisent-lex-match text default rules usequal))
            (if term
                (setq wlex (cons term (cons text (cons beg end)))
                      ;; Eat input stream
                      wisent-lex-istream (nthcdr n is))
              (setq n    (1- n)
                    ends (cdr ends)))))
           
         ;; One/one token mapping
         ((setq usequal (wisent-lex-token-get stok 'string)
                term (wisent-lex-match text default rules usequal))
          (setq wlex (cons term
                           (cons text
                                 (semantic-lex-token-bounds flex)))
                ;; Eat input stream
                wisent-lex-istream (cdr is))))))
      
    ;; Return value found or default one
    (or wlex
        (cons (if (wisent-lex-token-get stok 'char-literal)
                  (aref text 0)
                stok)
              (cons text (semantic-lex-token-bounds flex))))))

(define-wisent-lexer wisent-lex
  "Return the next available lexical token in Wisent's form.
The variable `wisent-lex-istream' contains the list of lexical tokens
produced by `semantic-lex'.  Pop the next token available and convert
it to a form suitable for the Wisent's parser."
  (let* ((tk (car wisent-lex-istream)))
    ;; Eat input stream
    (setq wisent-lex-istream (cdr wisent-lex-istream))
    (cons (semantic-lex-token-class tk)
          (cons (semantic-lex-token-text tk)
                (semantic-lex-token-bounds tk)))))

;;; Syntax analysis
;;
(defvar wisent-error-function #'ignore
  "Function used to report parse error.")
(make-variable-buffer-local 'wisent-error-function)

(defvar wisent-lexer-function #'wisent-lex
  "Function used to obtain the next lexical token in input.
Should be a lexical analyzer created with `define-wisent-lexer'.")
(make-variable-buffer-local 'wisent-lexer-function)

;; Tag production
;;
(defsubst wisent-token (&rest return-val)
  "Return a raw Semantic token including RETURN-VAL.
Should be used in Semantic actions to build the bovine cache."
  (nconc return-val
         (if (or $region
                 (setq $region (nthcdr 2 wisent-input)))
             (list (car $region) (cdr $region))
           (list (point-max) (point-max)))))

(defmacro wisent-cooked-token (&rest return-val)
  "Return a cooked Semantic token including RETURN-VAL.
Should be used in Semantic actions to build the bovine cache."
  `(let* ((cooked (semantic-raw-to-cooked-token
                   (wisent-token ,@return-val)))
          (l cooked))
     (while l
       (semantic-token-put (car l) 'reparse-symbol $nterm)
       (setq l (cdr l)))
     cooked))

;; Unmatched syntax collector
;;
(defun wisent-collect-unmatched-syntax (nomatch)
  "Add lexical token NOMATCH to the cache of unmatched tokens.
See also the variable `semantic-unmatched-syntax-cache'.

NOMATCH is in Wisent's form: (SYMBOL VALUE START . END)
and will be collected in `semantic-lex' form: (SYMBOL START . END)."
  (let ((region (cddr nomatch)))
    (and (number-or-marker-p (car region))
         (number-or-marker-p (cdr region))
         (setq semantic-unmatched-syntax-cache
               (cons (cons (car nomatch) region)
                     semantic-unmatched-syntax-cache)))))

;; Parser plug-ins
;;
;; The following functions permit to plug the Wisent LALR parser in
;; Semantic toolkit.  They use the standard API provided by Semantic
;; to plug parsers in.
;;
;; Two plug-ins are available, BUT ONLY ONE MUST BE USED AT A TIME:
;;
;; - `wisent-parse-stream' designed to override the standard function
;;   `semantic-parse-stream'.
;;
;; - `wisent-parse-region' designed to override the standard function
;;   `semantic-parse-region'.
;;
;; The latter should be faster because it eliminates a lot of function
;; call.
;;
(defun wisent-parse-stream (stream goal)
  "Parse STREAM using the Wisent LALR parser.
GOAL is a nonterminal symbol to start parsing at.
Return the list (STREAM SEMANTIC-STREAM) where STREAM are those
elements of STREAM that have not been used.  SEMANTIC-STREAM is the
list of semantic tokens found.
The LALR parser automaton must be available in buffer local variable
`semantic-toplevel-bovine-table'.

Must be installed by `semantic-install-function-overrides' to override
the standard function `semantic-parse-stream'."
  (let (wisent-lex-istream wisent-lex-lookahead lookahead cache)
    (if (vectorp (caar stream))
        (setq lookahead (aref (caar stream) 0)
              wisent-lex-lookahead lookahead
              stream (cdr stream)))
    (setq wisent-lex-istream stream
          cache (condition-case nil
                    (wisent-parse semantic-toplevel-bovine-table
                                  wisent-lexer-function
                                  wisent-error-function
                                  goal)
                  (error nil)))
    (if wisent-lookahead
        (if (eq lookahead wisent-lookahead)
            (progn
              (setq cache nil)
              ;; collect unmatched token here
              (run-hook-with-args
               'wisent-discarding-token-functions lookahead)
              )
          ;; push back the lookahead token
          (setq wisent-lex-istream
                (cons (cons (vector wisent-lookahead)
                            (cddr wisent-lookahead))
                      wisent-lex-istream))))
    (list wisent-lex-istream
          (if (consp cache) cache '(nil))
          )))

(defun wisent-parse-region (start end &optional goal depth returnonerror)
  "Parse the area between START and END using the Wisent LALR parser.
Return the list of semantic tokens found.
Optional arguments GOAL is a nonterminal symbol to start parsing at,
DEPTH is the lexical depth to scan, and RETURNONERROR is a flag to
stop parsing on syntax error, when non-nil.
The LALR parser automaton must be available in buffer local variable
`semantic-toplevel-bovine-table'.

Must be installed by `semantic-install-function-overrides' to override
the standard function `semantic-parse-region'."
  (if (or (< start (point-min)) (> end (point-max)) (< end start))
      (error "Invalid bounds [%s %s] passed to `wisent-parse-region'"
             start end))
  (let* ((case-fold-search semantic-case-fold)
         (wisent-lex-istream (semantic-lex start end depth))
         ptree token cooked oldla wisent-lex-lookahead)
    (while wisent-lex-istream
      ;; parse
      (setq oldla wisent-lex-lookahead
            token (condition-case nil
                      (wisent-parse semantic-toplevel-bovine-table
                                    wisent-lexer-function
                                    wisent-error-function
                                    goal)
                    (error nil)))
      ;; manage the lookahead token
      (if (and wisent-lookahead (eq oldla wisent-lookahead))
          (progn
            (setq wisent-lex-lookahead nil
                  token nil)
            ;; collect unmatched token here
            (run-hook-with-args
             'wisent-discarding-token-functions wisent-lookahead))
        (setq wisent-lex-lookahead wisent-lookahead))
      ;; cook result or return on syntax error
      (cond
       ((consp token)
        (setq cooked (semantic-raw-to-cooked-token token)
              ptree (append cooked ptree))
        (while cooked
          (setq token  (car cooked)
                cooked (cdr cooked))
          (or (semantic-token-get token 'reparse-symbol)
              (semantic-token-put token 'reparse-symbol goal)))
        )
       (returnonerror
        (setq wisent-lex-istream nil)
        ))
      ;; work in progress...
      (if wisent-lex-istream
	  (if (eq semantic-bovination-working-type 'percent)
	      (working-status
               (/ (* 100 (semantic-lex-token-start
                          (car wisent-lex-istream)))
                  (point-max)))
	    (working-dynamic-status))))
    ;; return parse tree
    (nreverse ptree)))

(provide 'wisent-bovine)

;;; wisent-bovine.el ends here
