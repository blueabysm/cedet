;;; bovine-grammar.el --- Bovine's input grammar mode
;;
;; Copyright (C) 2002, 2003 David Ponce
;;
;; Author: David Ponce <david@dponce.com>
;; Maintainer: David Ponce <david@dponce.com>
;; Created: 26 Aug 2002
;; Keywords: syntax
;; X-RCS: $Id: bovine-grammar.el,v 1.10 2003-03-21 03:25:49 zappo Exp $
;;
;; This file is not part of GNU Emacs.
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2, or (at
;; your option) any later version.
;;
;; This software is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:
;; 
;; Major mode for editing Bovine's input grammar (.by) files.

;;; History:
;; 

;;; Code:
(require 'semantic-grammar)

;;; Conversion routines
;;
(defsubst bovine-grammar-expand-EXPAND (parms quotemode)
  "Expand built-in EXPAND expression.
PARMS is EXPAND's parameter list.
QUOTEMODE is the current mode of quotation."
  (bovine-grammar-expand-form
   `(semantic-bovinate-from-nonterminal
     (car ,(car parms)) (cdr ,(car parms)) ',(cadr parms))
   quotemode t))

(defsubst bovine-grammar-expand-EXPANDFULL (parms quotemode)
  "Expand built-in EXPANDFULL expression.
PARMS is EXPANDFULL's parameter list.
QUOTEMODE is the current mode of quotation."
  (bovine-grammar-expand-form
   `(semantic-parse-region
     (car ,(car parms)) (cdr ,(car parms)) ',(cadr parms) 1)
   quotemode t))

(defsubst bovine-grammar-expand-ASSOC (parms quotemode)
  "Expand built-in ASSOC expression.
PARMS is ASSOC's parameter list.
QUOTEMODE is the current mode of quotation."
  ;; Substitute ASSOC by call to `semantic-bovinate-make-assoc-list'
  ;; and expand the whole expression.
  (bovine-grammar-expand-form
   (apply #'semantic-grammar-ASSOC parms) quotemode t))

(defsubst bovine-grammar-expand-TAG (parms quotemode)
  "Expand TAG expression.
PARMS is the parameter list.
QUOTEMODE is the current mode of quotation."
  (bovine-grammar-expand-form
   `(semantic-tag ,@parms)
   quotemode t))

(defsubst bovine-grammar-expand-VARIABLE-TAG (parms quotemode)
  "Expand built-in VARIABLE-TAG expression.
PARMS is the parameter list.
QUOTEMODE is the current mode of quotation."
  (bovine-grammar-expand-form
   `(semantic-tag-new-variable ,@parms)
   quotemode t))

(defsubst bovine-grammar-expand-FUNCTION-TAG (parms quotemode)
  "Expand built-in FUNCTION-TAG expression.
PARMS is the parameter list.
QUOTEMODE is the current mode of quotation."
  (bovine-grammar-expand-form
   `(semantic-tag-new-function ,@parms)
   quotemode t))

(defsubst bovine-grammar-expand-TYPE-TAG (parms quotemode)
  "Expand built-in TYPE-TAG expression.
PARMS is the parameter list.
QUOTEMODE is the current mode of quotation."
  (bovine-grammar-expand-form
   `(semantic-tag-new-type ,@parms)
   quotemode t))

(defsubst bovine-grammar-expand-INCLUDE-TAG (parms quotemode)
  "Expand built-in INCLUDE-TAG expression.
PARMS is the parameter list.
QUOTEMODE is the current mode of quotation."
  (bovine-grammar-expand-form
   `(semantic-tag-new-include ,@parms)
   quotemode t))

(defsubst bovine-grammar-expand-PACKAGE-TAG (parms quotemode)
  "Expand built-in PACKAGE-TAG expression.
PARMS is the parameter list.
QUOTEMODE is the current mode of quotation."
  (bovine-grammar-expand-form
   `(semantic-tag-new-package ,@parms)
   quotemode t))

(defsubst bovine-grammar-expand-CODE-TAG (parms quotemode)
  "Expand built-in PACKAGE-TAG expression.
PARMS is the parameter list.
QUOTEMODE is the current mode of quotation."
  (bovine-grammar-expand-form
   `(semantic-tag-new-code ,@parms)
   quotemode t))

(defun bovine-grammar-expand-form (form quotemode &optional inplace)
  "Expand FORM into a new one suitable to the bovine parser.
FORM is a list in which we are substituting.
Argument QUOTEMODE is non-nil if we are in backquote mode.
When non-nil, optional argument INPLACE indicates that FORM is being
expanded from elsewhere."
  (when (eq (car form) 'quote)
    (setq form (cdr form))
    (cond
     ((and (= (length form) 1) (listp (car form)))
      (insert "\n(append")
      (bovine-grammar-expand-form (car form) quotemode nil)
      (insert ")")
      (setq form nil inplace nil)
      )
     ((and (= (length form) 1) (symbolp (car form)))
      (insert "\n'" (symbol-name (car form)))
      (setq form nil inplace nil)
      )
     (t
      (insert "\n(list")
      (setq inplace t)
      )
     ))
  (cond
   ((eq (car form) 'EXPAND)
    (bovine-grammar-expand-EXPAND (cdr form) quotemode)
    )
   ((eq (car form) 'EXPANDFULL)
    (bovine-grammar-expand-EXPANDFULL (cdr form) quotemode)
    )
   ((eq (car form) 'ASSOC)
    (bovine-grammar-expand-ASSOC (cdr form) quotemode)
    )
   ((eq (car form) 'TAG)
    (bovine-grammar-expand-TAG (cdr form) quotemode)
    )
   ((eq (car form) 'VARIABLE-TAG)
    (bovine-grammar-expand-VARIABLE-TAG (cdr form) quotemode)
    )
   ((eq (car form) 'FUNCTION-TAG)
    (bovine-grammar-expand-FUNCTION-TAG (cdr form) quotemode)
    )
   ((eq (car form) 'TYPE-TAG)
    (bovine-grammar-expand-TYPE-TAG (cdr form) quotemode)
    )
   ((eq (car form) 'INCLUDE-TAG)
    (bovine-grammar-expand-INCLUDE-TAG (cdr form) quotemode)
    )
   ((eq (car form) 'PACKAGE-TAG)
    (bovine-grammar-expand-PACKAGE-TAG (cdr form) quotemode)
    )
   ((eq (car form) 'CODE-TAG)
    (bovine-grammar-expand-CODE-TAG (cdr form) quotemode)
    )
   (t
    (if inplace (insert "\n("))
    (let (inlist first n q x val)
      (while form
        (setq first (car form)
              form  (cdr form))
        (cond
         ((eq first nil)
          (when (and (not inlist) (not inplace))
            (insert "\n(list")
            (setq inlist t))
          (insert " nil")
          )
         ((listp first)
          ;;(let ((fn (and (symbolp (caar form)) (fboundp (caar form)))))
          (when (and (not inlist) (not inplace))
            (insert "\n(list")
            (setq inlist t))
          ;;(if (and inplace (not fn) (not (eq (caar form) 'EXPAND)))
          ;;    (insert " (append"))
          (bovine-grammar-expand-form
           first quotemode t) ;;(and fn (not (eq fn 'quote))))
          ;;(if (and inplace (not fn) (not (eq (caar form) 'EXPAND)))
          ;;    (insert  ")"))
          ;;)
          )
         ((symbolp first)
          (setq n (symbol-name first)   ;the name
                q quotemode             ;implied quote flag
                x nil)                  ;expand flag
          (if (eq (aref n 0) ?,)
              (if quotemode
                  ;; backquote mode needs the @
                  (if (eq (aref n 1) ?@)
                      (setq n (substring n 2)
                            q nil
                            x t)
                    ;; non backquote mode behaves normally.
                    (setq n (substring n 1)
                          q nil))
                (setq n (substring n 1)
                      x t)))
          (if (string= n "")
              (progn
                ;; We expand only the next item in place (a list?)
                ;; A regular inline-list...
                (bovine-grammar-expand-form (car form) quotemode t)
                (setq form (cdr form)))
            (if (and (eq (aref n 0) ?$)
                     ;; Don't expand $ tokens in implied quote mode.
                     ;; This acts like quoting in other symbols.
                     (not q))
                (progn
                  (cond
                   ((and (not x) (not inlist) (not inplace))
                    (insert "\n(list"))
                   ((and x inlist (not inplace))
                    (insert ")")
                    (setq inlist nil)))
                  (insert "\n(nth " (int-to-string
                                     (1- (string-to-int
                                          (substring n 1))))
                          " vals)")
                  (and (not x) (not inplace)
                       (setq inlist t)))
              
              (when (and (not inlist) (not inplace))
                (insert "\n(list")
                (setq inlist t))
              (or (char-equal (char-before) ?\()
                  (insert " "))
              (insert (if (or inplace (eq first t))
                          "" "'")
                      n))) ;; " "
          )
         (t
          (when (and (not inlist) (not inplace))
            (insert "\n(list")
            (setq inlist t))
          (insert (format "\n%S" first))
          )
         ))
      (if inlist (insert ")")))
    (if inplace (insert ")"))
    )
   ))

(defun bovine-grammar-expand-action (textform quotemode)
  "Expand semantic action string TEXTFORM into Lisp code.
QUOTEMODE is the mode in which quoted symbols are slurred."
  (if (string= "" textform)
      nil
    (let ((sexp (read textform)))
      ;; We converted the lambda string into a list.  Now write it
      ;; out as the bovine lambda expression, and do macro-like
      ;; conversion upon it.
      (insert "\n")
      (cond
       ((eq (car sexp) 'EXPAND)
        (insert ",(lambda (vals start end)")
        (bovine-grammar-expand-EXPAND (cdr sexp) quotemode)
        )
       ((and (listp (car sexp)) (eq (caar sexp) 'EVAL))
        ;; The user wants to evaluate the following args.
        ;; Use a simpler expander
        )
       (t
        (insert ",(semantic-lambda")
        (bovine-grammar-expand-form sexp quotemode)
        ))
      (insert ")\n"))))

(defun bovine-grammar-parsetable-builder ()
  "Return the parser table expression as a string value."
  (let* ((start      (semantic-grammar-start))
         (scopestart (semantic-grammar-scopestart))
         (quotemode  (semantic-grammar-quotemode))
         (tokens     (semantic-find-nonterminal-by-token
                      'token (current-buffer)))
         (nterms     (semantic-find-nonterminal-by-token
                      'nonterminal (current-buffer)))
         nterm rules items item actn prec token type regex)
    (when start
      (if (cdr start)
          (message "Extra start symbols %S ignored" (cdr start)))
      (setq start (symbol-name (car start))))
    (when scopestart
      (setq scopestart (symbol-name scopestart)))
    (with-temp-buffer
      (erase-buffer)
      (insert "`(")
      ;; Process each nonterminal
      (while nterms
        (setq nterm  (car nterms)
	      ;; We can't use the override form because the current buffer
	      ;; is not the originator of the token.
              rules  (semantic-nonterminal-children-semantic-grammar-mode nterm)
              nterm  (semantic-token-name nterm)
              nterms (cdr nterms))
        (cond
         ;; Replace the start symbol by bovine-toplevel
         ((equal nterm start)
          (insert "\n(bovine-toplevel ;;" nterm))
         ;; Replace the scopestart symbol by bovine-inner-scope
         ((equal nterm scopestart)
          (insert "\n(bovine-inner-scope ;;" nterm))
         (t
          (insert "\n(" nterm)))
        ;; Process each rule
        (while rules
          (setq items (semantic-token-extra-spec (car rules) :value)
                prec  (semantic-token-extra-spec (car rules) :prec)
                actn  (semantic-token-extra-spec (car rules) :expr)
                rules (cdr rules))
          ;; Process each item
          (insert "\n(")
          (if (null items)
              ;; EMPTY rule
              (insert ";;EMPTY" (if actn "" "\n"))
            ;; Expand items
            (while items
              (setq item  (car items)
                    items (cdr items))
              (if (consp item) ;; mid-rule action
                  (message "Mid-rule action %S ignored" item)
                (or (char-equal (char-before) ?\()
                    (insert "\n"))
                (cond
                 ;; Replace ITEM by bovine-toplevel
                 ((equal item start)
                  (insert "bovine-toplevel"))
                 ;; Replace ITEM by bovine-inner-scope
                 ((equal item scopestart)
                  (insert "bovine-inner-scope"))
                 ;; Replace ITEM by its %token definition.
                 ;; If a '%token TYPE ITEM [REGEX]' definition exists
                 ;; in the grammar, ITEM is replaced by TYPE [REGEX].
                 ((setq token (semantic-find-nonterminal-by-name
                               item tokens)
                        type  (semantic-token-extra-spec token :type))
                  (insert type)
                  (if (setq regex (semantic-token-extra-spec token :value))
                      (insert (format "\n%S" regex))))
                 ;; Don't change ITEM
                 (t
                  (insert (semantic-grammar-item-text item)))
                 ))))
          (if prec
              (message "%prec %S ignored" prec))
          (if actn
              (bovine-grammar-expand-action actn quotemode))
          (insert ")"))
        (insert "\n) ;; end " nterm "\n"))
      (insert ")\n")
      (buffer-string))))

(defun bovine-grammar-setupcode-builder ()
  "Return the text of the setup code."
  (format
   "(progn\n\
        (setq semantic-toplevel-bovine-table %s\n\
              semantic-debug-parser-source %S\n\
              semantic-debug-parser-class 'semantic-bovine-debug-parser
              semantic-flex-keywords-obarray %s\n\
              %s)\n\
       %s)"
   (semantic-grammar-parsetable)
   (file-name-nondirectory (buffer-file-name))
   (semantic-grammar-keywordtable)
   (let ((mode (semantic-grammar-languagemode)))
     ;; Is there more than one major mode?
     (if (and (listp mode) (> (length mode) 1))
         (format "semantic-equivalent-major-modes '%S\n" mode)
       ""))
   (semantic-grammar-setupcode-text)))

;;;###autoload
(define-derived-mode bovine-grammar-mode semantic-grammar-mode "BY"
  "Major mode for editing Bovine grammars."
  (semantic-install-function-overrides
   '((grammar-parsetable-builder . bovine-grammar-parsetable-builder)
     (grammar-setupcode-builder  . bovine-grammar-setupcode-builder)
     )))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.by$" . bovine-grammar-mode))

;;;###autoload
(eval-after-load "speedbar"
  '(speedbar-add-supported-extension ".by"))

(provide 'bovine-grammar)

;;; bovine-grammar.el ends here
