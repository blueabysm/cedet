;;; semantic-util.el --- Utilities for use with semantic tag tables

;;; Copyright (C) 1999, 2000, 2001, 2002, 2003 Eric M. Ludlam

;; Author: Eric M. Ludlam <zappo@gnu.org>
;; Keywords: syntax
;; X-RCS: $Id: semantic-util.el,v 1.110 2003-04-01 03:46:34 zappo Exp $

;; This file is not part of GNU Emacs.

;; Semantic is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; This software is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:
;;
;; API for acessing and searching nonterminal streams from the
;; Semantic Bovinator.
;;

(require 'assoc)
(require 'semantic)
(eval-when-compile
  ;; Emacs 21
  (condition-case nil
      (require 'newcomment)
    (error nil))
  )

;;; Code:

(defvar semantic-type-relation-separator-character '(".")
  "Character strings used to separate a parent/child relationship.
This list of strings are used for displaying or finding separators
in variable field dereferencing.  The first character will be used for
display.  In C, a type field is separated like this: \"type.field\"
thus, the character is a \".\".  In C, and additional value of \"->\"
would be in the list, so that \"type->field\" could be found.")
(make-variable-buffer-local 'semantic-type-relation-separator-character)

(defvar semantic-equivalent-major-modes nil
  "List of major modes which are considered equivalent.
Equivalent modes share a parser, and a set of override methods.
Setup from the BNF code generator.  A value of nil means that
the current major mode is the only one.")
(make-variable-buffer-local 'semantic-equivalent-major-modes)

;; These semanticdb calls will throw warnings in the byte compiler.
;; Doing the right thing to make them available at compile time
;; really messes up the compilation sequence.
(defun semantic-file-tag-table (file &optional checkcache)
  "Return a tag table for FILE.
If it is loaded, return the stream after making sure it's ok.
If FILE is not loaded, check to see if `semanticdb' feature exists,
   and use it to get tags from files not in memory.
If FILE is not loaded, and semanticdb is not available, find the file
   and parse it.
Optional argument CHECKCACHE is passed to `semantic-bovinate-toplevel'."
  (if (get-file-buffer file)
      (save-excursion
	(set-buffer (get-file-buffer file))
	(semantic-bovinate-toplevel checkcache))
    ;; File not loaded
    (if (and (fboundp 'semanticdb-minor-mode-p)
	     (semanticdb-minor-mode-p))
	;; semanticdb is around, use it.
	(semanticdb-file-stream file)
      ;; Get the stream ourselves.
      (save-excursion
	(set-buffer (find-file-noselect file))
	(semantic-bovinate-toplevel checkcache)))))

(semantic-alias-obsolete 'semantic-file-token-stream
			 'semantic-file-tag-table)

(defun semantic-something-to-tag-table (something)
  "Convert SOMETHING into a semantic tag table.
Something can be a tag with a valid BUFFER property, a tag table, a
buffer, or a filename.  If SOMETHING is nil, use the current buffer."
  (cond
   ;; A list of tags
   ((and (listp something)
	 (semantic-tag-p (car something)))
    something)
   ;; A buffer
   ((bufferp something)
    (save-excursion
      (set-buffer something)
      (semantic-bovinate-toplevel t)))
   ;; A Tag: Get that tag's buffer
   ((and (semantic-tag-with-position-p something)
	 (semantic-tag-buffer))
    (save-excursion
      (set-buffer (semantic-tag-buffer something))
      (semantic-bovinate-toplevel t)))
   ;; Tag with a file name in it
   ((and (semantic-tag-p something)
	 (semantic-tag-file-name something)
	 (file-exists-p (semantic-tag-file-name something)))
    (semantic-file-tag-table
     (semantic-tag-file-name something)))
   ;; A file name
   ((and (stringp something)
	 (file-exists-p something))
    (semantic-file-tag-table something nil))
   ;; Use the current buffer for nil
;;   ((null something)
;;    (semantic-bovinate-toplevel t))
   ;; don't know what it is
   (t nil)))

(semantic-alias-obsolete 'semantic-something-to-stream
			 'semantic-something-to-tag-table)

;;; Bucketizing: Take and convert the tags based on type.
;;
(defvar semantic-bucketize-token-token
  ;; Must use lambda because `semantic-tag-class' is a macro.
  (lambda (tok) (semantic-tag-class tok))
  "Function used to get a symbol describing the class of a token.
This function must take one argument of a semantic token.
It should return a symbol found in `semantic-symbol->name-assoc-list'
which `semantic-bucketize' uses to bin up tokens.
To create new bins for an application augment
`semantic-symbol->name-assoc-list', and
`semantic-symbol->name-assoc-list-for-type-parts' in addition
to setting this variable (locally in your function).")

(defun semantic-bucketize (tokens &optional parent filter)
  "Sort TOKENS into a group of buckets based on token type.
Unknown types are placed in a Misc bucket.
Type bucket names are defined by either `semantic-symbol->name-assoc-list'.
If PARENT is specified, then TOKENS belong to this PARENT in some way.
This will use `semantic-symbol->name-assoc-list-for-type-parts' to
generate bucket names.
Optional argument FILTER is a filter function to be applied to each bucket.
The filter function will take one argument, which is a list of tokens, and
may re-organize the list with side-effects."
  (let* ((name-list (if parent
			semantic-symbol->name-assoc-list-for-type-parts
		      semantic-symbol->name-assoc-list))
	 (sn name-list)
	 (bins (make-vector (1+ (length sn)) nil))
	 ask toktype
	 (nsn nil)
	 (num 1)
	 (out nil))
    ;; Build up the bucket vector
    (while sn
      (setq nsn (cons (cons (car (car sn)) num) nsn)
	    sn (cdr sn)
	    num (1+ num)))
    ;; Place into buckets
    (while tokens
      (setq toktype (funcall semantic-bucketize-token-token (car tokens))
	    ask (assq toktype nsn)
	    num (or (cdr ask) 0))
      (aset bins num (cons (car tokens) (aref bins num)))
      (setq tokens (cdr tokens)))
    ;; Remove from buckets into a list.
    (setq num 1)
    (while (< num (length bins))
      (when (aref bins num)
	(setq out
	      (cons (cons
		     (cdr (nth (1- num) name-list))
		     ;; Filtering, First hacked by David Ponce david@dponce.com
		     (funcall (or filter 'nreverse) (aref bins num)))
		    out)))
      (setq num (1+ num)))
    (if (aref bins 0)
	(setq out (cons (cons "Misc"
			      (funcall (or filter 'nreverse) (aref bins 0)))
			out)))
    (nreverse out)))

;;; Adopt external children by rebuilding the list
;;
(defvar semantic-orphaned-member-metaparent-type "class"
  "In `semantic-adopt-external-members', the type of 'type for metaparents.
A metaparent is a made-up type semantic token used to hold the child list
of orphaned members of a named type.")
(make-variable-buffer-local 'semantic-orphaned-member-metaparent-type)

(defvar semantic-mark-external-member-function nil
  "Function called when an externally defined orphan is found.
Be default, the token is always marked with the `adopted' property.
This function should be locally bound by a program that needs
to add additional behaviors into the token list.
This function is called with two arguments.  The first is TOKEN which is
a shallow copy of the token to be modified.  The second is the PARENT
which is adopting TOKEN.  This function should return TOKEN (or a copy of it)
which is then integrated into the revised token list.")

(defun semantic-adopt-external-members (tags)
  "Rebuild TAGS so that externally defined members are regrouped.
Some languages such as C++ and CLOS permit the declaration of member
functions outside the definition of the class.  It is easier to study
the structure of a program when such methods are grouped together
more logically.

This function uses `semantic-nonterminal-external-member-p' to
determine when a potential child is an externally defined member.

Note: Applications which use this function must account for token
types which do not have a position, but have children which *do*
have positions.

Applications should use `semantic-mark-external-member-function'
to modify all tags which are found as externally defined to some
type.  For example, changing the token type for generating extra
buckets with the bucket function."
  (let ((parent-buckets nil)
	(decent-list nil)
	(out nil)
	(tmp nil)
	)
    ;; Rebuild the output list, stripping out all parented
    ;; external entries
    (while tags
      (cond
       ((setq tmp (semantic-nonterminal-external-member-parent (car tags)))
	(let ((tagcopy (semantic-tag-clone (car tags)))
	      (a (assoc tmp parent-buckets)))
	  (semantic--tag-put-property-no-side-effect tagcopy 'adopted t)
	  (if a
	      ;; If this parent is already in the list, append.
	      (setcdr (nthcdr (1- (length a)) a) (list tagcopy))
	    ;; If not, prepend this new parent bucket into our list
	    (setq parent-buckets
		  (cons (cons tmp (list tagcopy)) parent-buckets)))
	  ))
       ((eq (semantic-tag-class (car tags)) 'type)
	;; Types need to be rebuilt from scratch so we can add in new
	;; children to the child list.  Only the top-level cons
	;; cells need to be duplicated so we can hack out the
	;; child list later.
	(setq out (cons (semantic-tag-clone (car tags)) out))
	(setq decent-list (cons (car out) decent-list))
	)
       (t
	;; Otherwise, append this tag to our new output list.
	(setq out (cons (car tags) out)))
       )
      (setq tags (cdr tags)))
    ;; Rescan out, by decending into all types and finding parents
    ;; for all entries moved into the parent-buckets.
    (while decent-list
      (let* ((bucket (assoc (semantic-tag-name (car decent-list))
			    parent-buckets))
	     (bucketkids (cdr bucket))
	     (partcdr (nthcdr 3 (car decent-list))))
	(when bucket
	  ;; Run our secondary marking function on the children
	  (if semantic-mark-external-member-function
	      (setq bucketkids
		    (mapcar (lambda (tok)
			      (funcall semantic-mark-external-member-function
				       tok (car decent-list)))
			    bucketkids)))
	  ;; We have some extra kids.  Merge.
	  (setcar partcdr (append (car partcdr) bucketkids))
	  ;; Nuke the bucket label so it is not found again.
	  (setcar bucket nil))
	(setq decent-list
	      (append (cdr decent-list)
		      ;; get embedded types to scan and make copies
		      ;; of them.
		      (mapcar
		       (lambda (tok) (semantic-tag-clone tok))
		       (semantic-find-tags-by-class 'type
			(semantic-tag-type-members (car decent-list)))))
	      )))
    ;; Scan over all remaining lost external methods, and tack them
    ;; onto the end.
    (while parent-buckets
      (if (car (car parent-buckets))
	  (let* ((tmp (car parent-buckets))
		 (fauxtok (semantic-tag-new-type
			   (car tmp)
			   semantic-orphaned-member-metaparent-type
			   nil ;; Part list
			   nil ;; parents (unknow)
			   ))
		 (partcdr (nthcdr 3 fauxtok))
		 (bucketkids (cdr tmp)))
	    (semantic--tag-put-property fauxtok 'faux t) ;; proprties
	    (if semantic-mark-external-member-function
		(setq bucketkids
		      (mapcar (lambda (tok)
				(funcall semantic-mark-external-member-function
					 tok fauxtok))
			      bucketkids)))
	    (setcar partcdr bucketkids)
	    ;; We have a bunch of methods with no parent in this file.
	    ;; Create a meta-type to hold it.
	    (setq out (cons fauxtok out))
	    ))
      (setq parent-buckets (cdr parent-buckets)))
    ;; Return the new list.
    (nreverse out)))

;; Some sorting functions
(defun semantic-string-lessp-ci (s1 s2)
  "Case insensitive version of `string-lessp'."
  ;; Use downcase instead of upcase because an average name
  ;; has more lower case characters.
  (string-lessp (downcase s1) (downcase s2)))

(defun semantic-sort-token-type (token)
  "Return a type string for TOKEN guaranteed to be a string."
  (let ((ty (semantic-tag-type token)))
    (cond ((stringp ty)
	   ty)
	  ((listp ty)
	   (or (car ty) ""))
	  (t ""))))

(defun semantic-sort-tokens-by-name-increasing (tokens)
  "Sort TOKENS by name in increasing order with side effects.
Return the sorted list."
  (sort tokens (lambda (a b)
		 (string-lessp (semantic-tag-name a)
			       (semantic-tag-name b)))))

(defun semantic-sort-tokens-by-name-decreasing (tokens)
  "Sort TOKENS by name in decreasing order with side effects.
Return the sorted list."
  (sort tokens (lambda (a b)
		 (string-lessp (semantic-tag-name b)
			       (semantic-tag-name a)))))

(defun semantic-sort-tokens-by-type-increasing (tokens)
  "Sort TOKENS by type in increasing order with side effects.
Return the sorted list."
  (sort tokens (lambda (a b)
		 (string-lessp (semantic-sort-token-type a)
			       (semantic-sort-token-type b)))))

(defun semantic-sort-tokens-by-type-decreasing (tokens)
  "Sort TOKENS by type in decreasing order with side effects.
Return the sorted list."
  (sort tokens (lambda (a b)
		 (string-lessp (semantic-sort-token-type b)
			       (semantic-sort-token-type a)))))

(defun semantic-sort-tokens-by-name-increasing-ci (tokens)
  "Sort TOKENS by name in increasing order with side effects.
Return the sorted list."
  (sort tokens (lambda (a b)
		 (semantic-string-lessp-ci (semantic-tag-name a)
					   (semantic-tag-name b)))))

(defun semantic-sort-tokens-by-name-decreasing-ci (tokens)
  "Sort TOKENS by name in decreasing order with side effects.
Return the sorted list."
  (sort tokens (lambda (a b)
		 (semantic-string-lessp-ci (semantic-tag-name b)
					   (semantic-tag-name a)))))

(defun semantic-sort-tokens-by-type-increasing-ci (tokens)
  "Sort TOKENS by type in increasing order with side effects.
Return the sorted list."
  (sort tokens (lambda (a b)
		 (semantic-string-lessp-ci (semantic-sort-token-type a)
					   (semantic-sort-token-type b)))))

(defun semantic-sort-tokens-by-type-decreasing-ci (tokens)
  "Sort TOKENS by type in decreasing order with side effects.
Return the sorted list."
  (sort tokens (lambda (a b)
		 (semantic-string-lessp-ci (semantic-sort-token-type b)
					   (semantic-sort-token-type a)))))

;;; Recursive searching through dependency trees
;;
;; This will depend on the general searching APIS defined above.
;; but will add full recursion through the dependencies list per
;; stream.
(defun semantic-recursive-find-nonterminal-by-name (name buffer)
  "Recursivly find the first occurance of NAME.
Start search with BUFFER.  Recurse through all dependencies till found.
The return item is of the form (BUFFER TOKEN) where BUFFER is the buffer
in which TOKEN (the token found to match NAME) was found.

THIS ISN'T USED IN SEMANTIC.  DELETE ME SOON.
"
  (save-excursion
    (set-buffer buffer)
    (let* ((stream (semantic-bovinate-toplevel))
	   (includelist (or (semantic-find-tags-by-class 'include stream)
			    "empty.silly.thing"))
	   (found (semantic-find-first-tag-by-name name stream))
	   (unfound nil))
      (while (and (not found) includelist)
	(let ((fn (semantic-find-dependency (car includelist))))
	  (if (and fn (not (member fn unfound)))
	      (save-excursion
		(set-buffer (find-file-noselect fn))
		(message "Scanning %s" (buffer-file-name))
		(setq stream (semantic-bovinate-toplevel))
		(setq found (semantic-find-first-tag-by-name name stream))
		(if found
		    (setq found (cons (current-buffer) (list found)))
		  (setq includelist
			(append includelist
				(semantic-find-tags-by-token
				 'include stream))))
		(setq unfound (cons fn unfound)))))
	(setq includelist (cdr includelist)))
      found)))
  
;;; Completion APIs
;;
;; These functions provide minibuffer reading/completion for lists of
;; nonterminals.
(defvar semantic-read-symbol-history nil
  "History for a symbol read.")

(defun semantic-read-symbol (prompt &optional default stream filter)
  "Read a symbol name from the user for the current buffer.
PROMPT is the prompt to use.
Optional arguments:
DEFAULT is the default choice.  If no default is given, one is read
from under point.
STREAM is the list of tokens to complete from.
FILTER is provides a filter on the types of things to complete.
FILTER must be a function to call on each element."
  (if (not default) (setq default (thing-at-point 'symbol)))
  (if (not stream) (setq stream (semantic-bovinate-toplevel)))
  (setq stream
	(if filter
	    (semantic-brute-find-tags-by-function filter stream)
	  (semantic-brute-find-tag-standard stream)))
  (if (and default (string-match ":" prompt))
      (setq prompt
	    (concat (substring prompt 0 (match-end 0))
		    " (default: " default ") ")))
  (completing-read prompt stream nil t ""
		   'semantic-read-symbol-history
		   default))

(defun semantic-read-variable (prompt &optional default stream)
  "Read a variable name from the user for the current buffer.
PROMPT is the prompt to use.
Optional arguments:
DEFAULT is the default choice.  If no default is given, one is read
from under point.
STREAM is the list of tokens to complete from."
  (semantic-read-symbol
   prompt default
   (or (semantic-find-tags-by-class
	'variable (or stream (current-buffer)))
       (error "No local variables"))))

(defun semantic-read-function (prompt &optional default stream)
  "Read a function name from the user for the current buffer.
PROMPT is the prompt to use.
Optional arguments:
DEFAULT is the default choice.  If no default is given, one is read
from under point.
STREAM is the list of tags to complete from."
  (semantic-read-symbol
   prompt default
   (or (semantic-find-tags-by-class
	'function (or stream (current-buffer)))
       (error "No local functions"))))

(defun semantic-read-type (prompt &optional default stream)
  "Read a type name from the user for the current buffer.
PROMPT is the prompt to use.
Optional arguments:
DEFAULT is the default choice.  If no default is given, one is read
from under point.
STREAM is the list of tags to complete from."
  (semantic-read-symbol
   prompt default
   (or (semantic-find-tags-by-class
	'type (or stream (current-buffer)))
       (error "No local types"))))


;;; Tag to text overload functions
;;
;; Abbreviations, prototypes, and coloring support.
(eval-when-compile (require 'font-lock))

(defvar semantic-token->text-functions
  '(semantic-name-nonterminal
    semantic-abbreviate-nonterminal
    semantic-summarize-nonterminal
    semantic-prototype-nonterminal
    semantic-concise-prototype-nonterminal
    semantic-uml-abbreviate-nonterminal
    semantic-uml-prototype-nonterminal
    semantic-uml-concise-prototype-nonterminal
    semantic-prin1-nonterminal
    )
  "List of functions which convert a token to text.
Each function must take the parameters TOKEN &optional PARENT COLOR.
TOKEN is the token to convert.
PARENT is a parent token or name which refers to the structure
or class which contains TOKEN.  PARENT is NOT a class which a TOKEN
would claim as a parent.
COLOR indicates that the generated text should be colored using
`font-lock'.")

(defvar semantic-token->text-custom-list
  (append '(radio)
	  (mapcar (lambda (f) (list 'const f))
		  semantic-token->text-functions)
	  '(function))
  "A List used by customizeable variables to choose a token to text function.
Use this variable in the :type field of a customizable variable.")

(defvar semantic-function-argument-separator ","
  "Text used to separate arguments when creating text from tokens.")
(make-variable-buffer-local 'semantic-function-argument-separator)

(defun semantic-test-all-token->text-functions ()
  "Test all outputs from `semantic-token->text-functions'.
Output is generated from the function under `point'."
  (interactive)
  (semantic-bovinate-toplevel t)
  (let* ((tok (semantic-current-tag))
	 (par (or (semantic-current-tag-parent)
		  (if (semantic-tag-function-parent tok)
		      (semantic-find-first-tag-by-name
		       (semantic-tag-function-parent tok)
		       (current-buffer)))
		  ))
	 (fns semantic-token->text-functions))
    (with-output-to-temp-buffer "*Token->text*"
      (princ "Token->text function tests:")
      (while fns
	(princ "\n")
	(princ (car fns))
	(princ ":\n ")
	(let ((s (funcall (car fns) tok par t)))
	  (save-excursion
	    (set-buffer "*Token->text*")
	    (goto-char (point-max))
	    (insert s)))
	(setq fns (cdr fns))))
      ))

(defvar semantic-face-alist
  `( (function . font-lock-function-name-face)
     (variable . font-lock-variable-name-face)
     (type . font-lock-type-face)
     ;; These are different between Emacsen.
     (include . ,(if (featurep 'xemacs)
		     'font-lock-preprocessor-face
		   'font-lock-constant-face))
     (package . ,(if (featurep 'xemacs)
		     'font-lock-preprocessor-face
		   'font-lock-constant-face))
     ;; Not a token, but instead a feature of output
     (label . font-lock-string-face)
     (comment . font-lock-comment-face)
     (keyword . font-lock-keyword-face)
     (abstract . italic)
     (static . underline)
     )
  "Face used to colorize tokens of different types.
Override the value locally if a language supports other token types.
When adding new elements, try to use symbols also returned by the parser.
The form of an entry in this list is of the form:
 ( SYMBOL .  FACE )
where SYMBOL is a token type symbol used with semantic.  FACE
is a symbol representing a face.
Faces used are generated in `font-lock' for consistency, and will not
be used unless font lock is a feature.")

;;; Coloring Functions
(defun semantic-colorize-text (text face-class)
  "Apply onto TEXT a color associated with FACE-CLASS.
FACE-CLASS is a token type found in `semantic-face-alist'.  See this variable
for details on adding new types."
  (when (featurep 'font-lock)
    (let ((face (cdr-safe (assoc face-class semantic-face-alist)))
	  (newtext (concat text)))
      (put-text-property 0 (length text) 'face face newtext)
      newtext)
    ))

(defun semantic-colorize-merge-text (precoloredtext face-class)
  "Apply onto PRECOLOREDTEXT a color associated with FACE-CLASS.
FACE-CLASS is a token type found in 'semantic-face-alist'.  See this
variable for details on adding new types."
  (let ((face (cdr-safe (assoc face-class semantic-face-alist)))
	(newtext (concat precoloredtext))
	)
    (if (featurep 'xemacs)
	(add-text-properties 0 (length newtext) (list 'face face) newtext)
      (alter-text-property 0 (length newtext) 'face
			   (lambda (current-face)
			     (let ((cf
				    (cond ((facep current-face)
					   (list current-face))
					  ((listp current-face)
					   current-face)
					  (t nil)))
				   (nf
				    (cond ((facep face)
					   (list face))
					  ((listp face)
					   face)
					  (t nil))))
			       (append cf nf)))
			   newtext))
    newtext))

;;; The token->text functions
(defun semantic-prin1-nonterminal (token &optional parent color)
  "Convert TOKEN to a string that is Emacs Lisp.
PARENT and COLOR are ignored."
  (format "%S" token))

(define-overload semantic-name-nonterminal (token &optional parent color)
  "Return the name string describing TOKEN.
The name is the shortest possible representation.
Optional argument PARENT is the parent type if TOKEN is a detail.
Optional argument COLOR means highlight the prototype with font-lock colors.")

(defun semantic-name-nonterminal-default (token &optional parent color)
  "Return an abbreviated string describing TOKEN.
Optional argument PARENT is the parent type if TOKEN is a detail.
Optional argument COLOR means highlight the prototype with font-lock colors."
  (let ((name (semantic-tag-name token))
	(destructor
	 (if (eq (semantic-tag-class token) 'function)
	     (semantic-tag-function-destructor-p token))))
    (when destructor
      (setq name (concat "~" name)))
    (if color
	(setq name (semantic-colorize-text name (semantic-tag-class token))))
    name))

(define-overload semantic-abbreviate-nonterminal (token &optional parent color)
  "Return an abbreviated string describing TOKEN.
The abbreviation is to be short, with possible symbols indicating
the type of token, or other information.
Optional argument PARENT is the parent type if TOKEN is a detail.
Optional argument COLOR means highlight the prototype with font-lock colors.")

(defun semantic-abbreviate-nonterminal-default (token &optional parent color)
  "Return an abbreviated string describing TOKEN.
Optional argument PARENT is a parent token in the token hierarchy.
In this case PARENT refers to containment, not inheritance.
Optional argument COLOR means highlight the prototype with font-lock colors.
This is a simple C like default."
  ;; Do lots of complex stuff here.
  (let ((tok (semantic-tag-class token))
	(name (semantic-name-nonterminal token parent color))
	(suffix "")
	str)
    (cond ((eq tok 'function)
	   (setq suffix "()"))
	  ((eq tok 'include)
	   (setq suffix "<>"))
	  ((eq tok 'variable)
	   (setq suffix (if (semantic-tag-variable-default token)
			    "=" "")))
	  )
    (setq str (concat name suffix))
    (if parent
	(setq str
	      (concat (semantic-name-nonterminal parent color)
		      (car semantic-type-relation-separator-character)
		      str)))
    str))

;; Semantic 1.2.x had this misspelling.  Keep it for backwards compatibiity.
(semantic-alias-obsolete 
 'semantic-summerize-nonterminal 'semantic-summarize-nonterminal)

(define-overload semantic-summarize-nonterminal (token &optional parent color)
  "Summarize TOKEN in a reasonable way.
Optional argument PARENT is the parent type if TOKEN is a detail.
Optional argument COLOR means highlight the prototype with font-lock colors.")

(defun semantic-summarize-nonterminal-default (token &optional parent color)
  "Summarize TOKEN in a reasonable way.
Optional argument PARENT is the parent type if TOKEN is a detail.
Optional argument COLOR means highlight the prototype with font-lock colors."
  (let* ((proto (semantic-prototype-nonterminal token nil color))
         (names (if parent
                    semantic-symbol->name-assoc-list-for-type-parts
                  semantic-symbol->name-assoc-list))
         (tsymb (funcall semantic-bucketize-token-token token))
         (label (capitalize (or (cdr-safe (assoc tsymb names))
                                (symbol-name tsymb)))))
    (if color
        (setq label (semantic-colorize-text label 'label)))
    (concat label ": " proto)))

(define-overload semantic-prototype-nonterminal (token &optional parent color)
  "Return a prototype for TOKEN.
This function should be overloaded, though it need not be used.
This is because it can be used to create code by language independent
tools.
Optional argument PARENT is the parent type if TOKEN is a detail.
Optional argument COLOR means highlight the prototype with font-lock colors.")

(defun semantic-prototype-nonterminal-default-args (args color)
  "Create a list of of strings for prototypes of ARGS.
ARGS can be a list of terminals, or a list of strings.
COLOR specifies if these arguments should be colored or not."
  (let ((out nil))
    (while args
      (cond ((stringp (car args))
	     (let ((a (car args)))
	       (if color
		   (setq a (semantic-colorize-text a 'variable)))
	       (setq out (cons a out))
	       ))
	    ((semantic-tag-p (car args))
	     (setq out
		   (cons (semantic-prototype-nonterminal (car args) nil color)
			 out))))
      (setq args (cdr args)))
    (nreverse out)))

(defun semantic-prototype-nonterminal-default (token &optional parent color)
  "Default method for returning a prototype for TOKEN.
This will work for C like languages.
Optional argument PARENT is the parent type if TOKEN is a detail.
Optional argument COLOR means highlight the prototype with font-lock colors."
  (let* ((tok (semantic-tag-class token))
	 (name (semantic-name-nonterminal token parent color))
	 (type (if (member tok '(function variable type))
		   (semantic-tag-type token)))
	 (args (semantic-prototype-nonterminal-default-args
		(cond ((eq tok 'function)
		       (semantic-tag-function-arguments token))
		      ((eq tok 'type)
		       (semantic-tag-type-members token))
		      (t nil))
		color))
	 (const (semantic-tag-get-attribute token 'const))
	 (mods (append
		(if const '("const") nil)
		(semantic-tag-get-attribute token 'typemodifiers)))
	 (array (if (eq tok 'variable)
		    (let ((deref
			   (semantic-tag-get-attribute 
 			    token 'dereference))
 			  (r ""))
 		      (while (and deref (/= deref 0))
 			(setq r (concat r "[]")
 			      deref (1- deref)))
 		      r)))
 	 (point (semantic-tag-get-attribute token 'pointer))
 	 (ref (semantic-tag-get-attribute token 'reference))
 	 )
    (if point (setq point (make-string point ?*)) "")
    (if args
	(setq args
	      (concat " "
		      (if (eq tok 'type) "{" "(")
		      (mapconcat (lambda (a) a) args
				 semantic-function-argument-separator)
		      (if (eq tok 'type) "}" ")"))))
    (if type
	(if (semantic-tag-p type)
	    (setq type (semantic-prototype-nonterminal type nil color))
	  (if (listp type)
	      (setq type (car type)))
	  (if color
	      (setq type (semantic-colorize-text type 'type)))))
    (concat (or mods "")
	    (if type (concat type " "))
	    point ref			;there should be only 1.
	    name
	    (or args "")
	    (or array ""))))

(define-overload semantic-concise-prototype-nonterminal (token &optional parent color)
  "Return a concise prototype for TOKEN.
Optional argument PARENT is the parent type if TOKEN is a detail.
Optional argument COLOR means highlight the prototype with font-lock colors.")

(defun semantic-concise-prototype-nonterminal-default (token &optional parent color)
  "Return a concise prototype for TOKEN.
This default function will make a cheap concise prototype using C like syntax.
Optional argument PARENT is the parent type if TOKEN is a detail.
Optional argument COLOR means highlight the prototype with font-lock colors."
  (let ((tok (semantic-tag-class token)))
    (cond
     ((eq tok 'type)
      (concat (semantic-name-nonterminal token parent color) "{}"))
     ((eq tok 'function)
      (let ((args (semantic-tag-function-arguments token)))
        (concat (semantic-name-nonterminal token parent color)
                " ("
                (if args
                    (cond ((stringp (car args))
			   (mapconcat
			    (if color
				(lambda (a) (semantic-colorize-text
					     a 'variable))
			      'identity)
			    args semantic-function-argument-separator))
			  ((semantic-tag-p (car args))
			   (mapconcat
			    (lambda (a)
			      (let ((ty (semantic-tag-type a)))
				(cond ((and (stringp ty) color)
				       (semantic-colorize-text ty 'type))
				      ((stringp ty)
				       ty)
				      ((semantic-tag-p ty)
				       (semantic-prototype-nonterminal
					ty parent nil))
				      ((and (consp ty) color)
				       (semantic-colorize-text (car ty) 'type))
				      ((consp ty)
				       (car ty))
				      (t (error "Concice-prototype")))))
			    args semantic-function-argument-separator))
			  ((consp (car args))
			   (mapconcat
			    (if color
				(lambda (a)
				  (semantic-colorize-text (car a) 'type))
			      'car)
			    args semantic-function-argument-separator))
			  (t (error "Concice-prototype")))
                  "")
                ")")))
     ((eq tok 'variable)
      (let* ((deref (semantic-tag-get-attribute
                     token 'dereference))
             (array "")
             )
        (while (and deref (/= deref 0))
          (setq array (concat array "[]")
                deref (1- deref)))
        (concat (semantic-name-nonterminal token parent color)
                array)))
     (t
      (semantic-abbreviate-nonterminal token parent color)))))

(defcustom semantic-uml-colon-string " : "
  "*String used as a color separator between parts of a UML string.
In UML, a variable may appear as `varname : type'.
Change this variable to change the output separator."
  :group 'semantic
  :type 'string)

(defcustom semantic-uml-no-protection-string ""
  "*String used to describe when no protection is specified.
Used by `semantic-uml-protection-to-string'."
  :group 'semantic
  :type 'string)

(defun semantic-uml-post-colorize (text token parent)
  "Add color to TEXT created from TOKEN and PARENT.
Adds augmentation for `abstract' and `static' entries."
  (if (semantic-nonterminal-abstract token parent)
      (setq text (semantic-colorize-merge-text text 'abstract)))
  (if (semantic-nonterminal-static token parent)
      (setq text (semantic-colorize-merge-text text 'static)))
  text
  )

(defun semantic-uml-attribute-string (token &optional parent)
  "Return a string for TOKEN, a child of PARENT representing a UML attribute.
UML attribute strings are things like {abstract} or {leaf}."
  (cond ((semantic-nonterminal-abstract token parent)
	 "{abstract}")
	((semantic-nonterminal-leaf token parent)
	 "{leaf}")
	))

(defun semantic-uml-protection-to-string (protection-symbol)
  "Convert PROTECTION-SYMBOL to a string for UML.
Default character returns are:
  public    -- +
  private   -- -
  protected -- #.
If PROTECTION-SYMBOL is unknown, then the return value is
`semantic-uml-no-protection-string'."
  (cond ((eq protection-symbol 'public)
	 "+")
	((eq protection-symbol 'private)
	 "-")
	((eq protection-symbol 'protected)
	 "#")
	(t semantic-uml-no-protection-string)))

(defun semantic-uml-token-or-string-to-string (token-or-string parent &optional args color)
  "Return a string representing the TOKEN-OR-STRING.
If TOKEN-OR-STRING is a token, create a UML like text output for it.
If TOKEN-OR-STRING is a string, just use that string as a variable.
PARENT is a token representing the parent of TOKEN-OR-STRING.
Append ARGS as a precolored string after the new text.
Colorize the new text based on COLOR."
  (cond ((stringp token-or-string)
	 (if color
	     (setq token-or-string
		   (semantic-colorize-text token-or-string 'variable)))
	 (concat token-or-string (or args "")))
	((semantic-tag-p token-or-string)
	 (let ((name (semantic-name-nonterminal token-or-string parent color))
	       (type  (semantic-tag-type token-or-string))
	       (point (semantic-tag-get-attribute token-or-string 'pointer))
	       (ref (semantic-tag-get-attribute token-or-string 'reference))
	       )
	   (if ref (setq ref "&"))	; only 1 reference?
	   (if point (setq point (make-string point ?*)) "")
	   (setq type
		 (cond ((semantic-tag-p type)
			(semantic-prototype-nonterminal type nil color))
		       ((and (listp type)
			     (stringp (car type)))
			(car type))
		       ((stringp type)
			type)
		       (t nil)))
	   (if (and type color)
	       (setq type (semantic-colorize-text type 'type)))
	   (setq name (concat name (or args "")))
	   (if type (concat name
			    semantic-uml-colon-string
			    type ref point)
	     name)))
	(t "")))

(define-overload semantic-uml-abbreviate-nonterminal (token &optional parent color)
  "Return a UML style abbreviation for TOKEN.
Optional argument PARENT is the parent type if TOKEN is a detail.
Optional argument COLOR means highlight the prototype with font-lock colors.")

(defun semantic-uml-abbreviate-nonterminal-default (token &optional parent color)
  "Return a UML style abbreviation for TOKEN.
Optional argument PARENT is the parent type if TOKEN is a detail.
Optional argument COLOR means highlight the prototype with font-lock colors."
  (let* ((text (semantic-uml-token-or-string-to-string
		token parent nil color))
	 (prot (semantic-nonterminal-protection token parent))
	 (protstr (semantic-uml-protection-to-string prot))
	 (text (concat protstr text)))
    (if color
	(setq text (semantic-uml-post-colorize text token parent)))
    text))

(defun semantic-uml-arguments-to-string (arguments color)
  "Convert ARGUMENTS to a string.
ARGUMENTS is a list as returned by semantic for an argument list.
Each element can be a s tring, or a psuedotoken (a token without
positional elements.
COLOR indicates if the string should be colorized."
  (concat " ("
	  (mapconcat (lambda (a)
		       (semantic-uml-token-or-string-to-string
			a nil nil color))
		     arguments
		     semantic-function-argument-separator)
	  ")"))

(define-overload semantic-uml-prototype-nonterminal (token &optional parent color)
  "Return a UML style prototype for TOKEN.
Optional argument PARENT is the parent type if TOKEN is a detail.
Optional argument COLOR means highlight the prototype with font-lock colors.")

(defun semantic-uml-prototype-nonterminal-default (token &optional parent color)
  "Return a UML style prototype for TOKEN.
Optional argument PARENT is the parent type if TOKEN is a detail.
Optional argument COLOR means highlight the prototype with font-lock colors."
  (let* ((tok (semantic-tag-class token))
	 (argtext nil)
	 (prot (semantic-nonterminal-protection token parent))
	 (text nil)
	 )
    (cond ((eq tok 'function)
	   (setq argtext (semantic-uml-arguments-to-string
			  (semantic-tag-function-arguments token)
			  color)))
	  ((eq tok 'type)
	   (setq argtext "{}")))
    (setq prot (semantic-uml-protection-to-string prot))
    (setq text (concat prot
		       (semantic-uml-token-or-string-to-string
			token parent argtext color)))
    (if color
	(setq text (semantic-uml-post-colorize text token parent)))
    text
    ))

(define-overload semantic-uml-concise-prototype-nonterminal (token &optional parent color)
  "Return a UML style concise prototype for TOKEN.
Optional argument PARENT is the parent type if TOKEN is a detail.
Optional argument COLOR means highlight the prototype with font-lock colors.")

(defun semantic-uml-concise-prototype-nonterminal-default (token &optional parent color)
  "Return a UML style concise prototype for TOKEN.
Optional argument PARENT is the parent type if TOKEN is a detail.
Optional argument COLOR means highlight the prototype with font-lock colors."
  (let* ((cp (semantic-concise-prototype-nonterminal token parent color))
	 (type (semantic-tag-type token))
	 (prot (semantic-nonterminal-protection token parent))
	 (text nil)
	 )
    (setq type
	  (cond ((semantic-tag-p type)
		 (semantic-prototype-nonterminal type nil color))
		((listp type)
		 (car type))
		((stringp type)
		 type)
		(t nil)))
    (setq prot (semantic-uml-protection-to-string prot))
    (setq text
	  (concat prot cp
		  (if type
		      (progn
			(setq type (semantic-colorize-text type 'type))
			(concat semantic-uml-colon-string type)))))
    (if color
	(setq text (semantic-uml-post-colorize text token parent)))
    text
    ))

;;; Multi-file Token information
;;
(defvar semantic-dependency-include-path nil
  "Defines the include path used when searching for files.
This should be a list of directories to search which is specific to
the file being included.
This variable can also be set to a single function.  If it is a
function, it will be called with one arguments, the file to find as a
string, and  it should return the full path to that file, or nil.")
(make-variable-buffer-local `semantic-dependency-include-path)

(defun semantic-find-dependency (&optional token)
  "Find the filename represented from TOKEN.
TOKEN may be a stripped element, in which case PARENT specifies a
parent token that has positinal information.
Depends on `semantic-dependency-include-path' for searching.  Always searches
`.' first, then searches additional paths."
  (if (not token)
      (setq token (car (semantic-find-tag-by-overlay nil))))

  (if (not (eq (semantic-tag-class token) 'include))
      (signal 'wrong-type-argument (list token 'include)))

  ;; First, see if this file exists in the current EDE projecy
  (if (and (fboundp 'ede-expand-filename) ede-minor-mode
	   (ede-expand-filename (ede-toplevel)
				(semantic-tag-name token)))
      (ede-expand-filename (ede-toplevel)
			   (semantic-tag-name token))
  
    (let ((s (semantic-fetch-overload 'find-dependency)))
      (if s (funcall s token)
	(save-excursion
	  (set-buffer (semantic-tag-buffer token))
	  (let ((name (semantic-tag-name token)))
	    (cond ((file-exists-p name)
		   (expand-file-name name))
		  ((and (symbolp semantic-dependency-include-path)
			(fboundp semantic-dependency-include-path))
		   (funcall semantic-dependency-include-path name))
		  (t
		   (let ((p semantic-dependency-include-path)
			 (found nil))
		     (while (and p (not found))
		       (if (file-exists-p (concat (car p) "/" name))
			   (setq found (concat (car p) "/" name)))
		       (setq p (cdr p)))
		     found)))))))))
(put 'semantic-find-dependency 'semantic-overload 'find-dependency)

(defun semantic-find-nonterminal (&optional token parent)
  "Find the location of TOKEN.
TOKEN may be a stripped element, in which case PARENT specifies a
parent token that has position information.
Different behaviors are provided depending on the type of token.
For example, dependencies (includes) will seek out the file that is
depended on, and functions will move to the specified definition."
  (if (not token)
      (setq token (car (semantic-find-tag-by-overlay nil))))
  (if (and (eq (semantic-tag-class token) 'include)
	   (let ((f (semantic-find-dependency token)))
	     (if f (find-file f))))
      nil
    (let ((s (semantic-fetch-overload 'find-nonterminal)))
      (if s (funcall s token parent)
	(if (semantic-tag-buffer token)
	    ;; If the token has no buffer, it may be deoverlayed.
	    ;; Assume the tool doing the finding knows that we came
	    ;; in from a database, and use the current buffer.
	    (set-buffer (semantic-tag-buffer token)))
	(if (semantic-tag-with-position-p token)
	    ;; If it's a number, go there
	    (goto-char (semantic-tag-start token))
	  ;; Otherwise, it's a trimmed vector, such as a parameter,
	  ;; or a structure part.
	  (if (not parent)
	      nil
	    (if (semantic-tag-with-position-p parent)
		(progn
		  (if (semantic-tag-buffer parent)
		      ;; If this parent tag has no buffer, then it
		      ;; may be deoverlayed.
		      (set-buffer (semantic-tag-buffer parent)))
		  (goto-char (semantic-tag-start parent))
		  ;; Here we make an assumtion that the text returned by
		  ;; the bovinator and concocted by us actually exists
		  ;; in the buffer.
		  (re-search-forward (semantic-tag-name token) nil t)))))))))
(put 'semantic-find-nonterminal 'semantic-overload 'find-nonterminal)

(defun semantic-find-documentation (&optional token nosnarf)
  "Find documentation from TOKEN and return it as a clean string.
TOKEN might have DOCUMENTATION set in it already.  If not, there may be
some documentation in a comment preceeding TOKEN's definition which we
cal look for.  When appropriate, this can be overridden by a language specific
enhancement.
Optional argument NOSNARF means to only return the flex token for it.
If nosnarf if 'flex, then only return the flex token."
  (if (not token)
      (setq token (car (semantic-find-tag-by-overlay nil))))
  (let ((s (semantic-fetch-overload 'find-documentation)))
    (if s (funcall s token nosnarf)
      ;; No override.  Try something simple to find documentation nearby
      (save-excursion
	(set-buffer (semantic-tag-buffer token))
	(semantic-find-nonterminal token)
	(or
	 ;; Is there doc in the token???
	 (if (semantic-tag-docstring token)
	     (if (stringp (semantic-tag-docstring token))
		 (semantic-tag-docstring token)
	       (goto-char (semantic-tag-docstring token))
	       (semantic-find-doc-snarf-comment nosnarf)))
	 ;; Check just before the definition.
	 (save-excursion
	   (re-search-backward comment-start-skip nil t)
	   (if (not (semantic-brute-find-tag-by-position
		     (point) (current-buffer) t))
	       ;; We found a comment that doesn't belong to the body
	       ;; of a function.
	       (semantic-find-doc-snarf-comment nosnarf)))
	 ;;  Lets look for comments either after the definition, but before code:
	 ;; Not sure yet.  Fill in something clever later....
	 nil
	 )))))
(put 'semantic-find-documentation 'semantic-overload 'find-documentation)


(defun semantic-find-doc-snarf-comment (nosnarf)
  "Snarf up the comment at POINT for `semantic-find-documentation'.
Attempt to strip out comment syntactic sugar.
Argument NOSNARF means don't modify the found text.
If NOSNARF is 'flex, then return the flex token."
  (let* ((semantic-ignore-comments nil)
	 (semantic-lex-analyzer #'semantic-comment-lexer))
    (if (eq nosnarf 'flex)
	(car (semantic-lex (point) (1+ (point))))
      (let ((ct (semantic-lex-token-text
		 (car (semantic-lex (point) (1+ (point)))))))
	(if nosnarf
	    nil
	  ;; ok, try to clean the text up.
	  ;; Comment start thingy
	  (while (string-match (concat "^\\s-*" comment-start-skip) ct)
	    (setq ct (concat (substring ct 0 (match-beginning 0))
			     (substring ct (match-end 0)))))
	  ;; Arbitrary punctuation at the beginning of each line.
	  (while (string-match "^\\s-*\\s.+\\s-*" ct)
	    (setq ct (concat (substring ct 0 (match-beginning 0))
			     (substring ct (match-end 0)))))
	  ;; End of a block comment.
	  (if (and block-comment-end (string-match block-comment-end ct))
	      (setq ct (concat (substring ct 0 (match-beginning 0))
			       (substring ct (match-end 0)))))
	  ;; In case it's a real string, STRIPIT.
	  (while (string-match "\\s-*\\s\"+\\s-*" ct)
	    (setq ct (concat (substring ct 0 (match-beginning 0))
			     (substring ct (match-end 0))))))
	;; Now return the text.
	ct))))

(defun semantic-prototype-file (buffer)
  "Return a file in which prototypes belonging to BUFFER should be placed.
Default behavior (if not overriden) looks for a token specifying the
prototype file, or the existence of an EDE variable indicating which
file prototypes belong in."
  (let ((s (semantic-fetch-overload 'prototype-file)))
    (if s
	(funcall s buffer)
      ;; Else, perform some default behaviors
      (if (and (fboundp 'ede-header-file) ede-minor-mode)
	  (save-excursion
	    (set-buffer buffer)
	    (ede-header-file))
	;; No EDE options for a quick answer.  Search.
	(save-excursion
	  (set-buffer buffer)
	  (if (re-search-forward "::Header:: \\([a-zA-Z0-9.]+\\)" nil t)
	      (match-string 1)))))))


;;;; Mode-specific Token information
;;
(define-overload semantic-nonterminal-external-member-parent (token)
  "Return a parent for TOKEN when TOKEN is an external member.
TOKEN is an external member if it is defined at a toplevel and
has some sort of label defing a parent.  The parent return will
be a string.

The default behavior, if not overriden with
`nonterminal-external-member-parent' is get the 'parent extra
specifier of TOKEN.

If this function is overriden, use
`semantic-nonterminal-external-member-parent-default' to also
include the default behavior, and merely extend your own."
  )

(defun semantic-nonterminal-external-member-parent-default (token)
  "Return the name of TOKENs parent iff TOKEN is not defined in it's parent."
  ;; Use only the extra spec because a type has a parent which
  ;; means something completely different.
  (let ((tp (semantic-tag-get-attribute token 'parent)))
    (when (stringp tp)
      tp)
    ))

(define-overload semantic-nonterminal-external-member-p (parent token)
  "Return non-nil if PARENT is the parent of TOKEN.
TOKEN is an external member of PARENT when it is somehow tagged
as having PARENT as it's parent.
PARENT and TOKEN must both be semantic tokens.

The default behavior, if not overriden with
`nonterminal-external-member-p' is to match 'parent extra specifier in
the name of TOKEN.

If this function is overriden, use
`semantic-nonterminal-external-member-children-p-default' to also
include the default behavior, and merely extend your own."
  )

(defun semantic-nonterminal-external-member-p-default (parent token)
  "Return non-nil if PARENT is the parent of TOKEN."
  ;; Use only the extra spec because a type has a parent which
  ;; means something completely different.
  (let ((tp (semantic-nonterminal-external-member-parent token)))
    (and (stringp tp)
	 (string= (semantic-tag-name parent) tp))
    ))

(define-overload semantic-nonterminal-external-member-children (token &optional usedb)
  "Return the list of children which are not *in* TOKEN.
If optional argument USEDB is non-nil, then also search files in
the Semantic Database.  If USEDB is a list of databases, search those
databases.

Children in this case are functions or types which are members of
TOKEN, such as the parts of a type, but which are not defined inside
the class.  C++ and CLOS both permit methods of a class to be defined
outside the bounds of the class' definition.

The default behavior, if not overriden with
`nonterminal-external-member-children' is to search using
`semantic-nonterminal-external-member-p' in all top level definitions
with a parent of TOKEN.

If this function is overriden, use
`semantic-nonterminal-external-member-children-default' to also
include the default behavior, and merely extend your own."
  )

(defun semantic-nonterminal-external-member-children-default (token &optional usedb)
  "Return list of external children for TOKEN.
Optional argument USEDB specifies if the semantic database is used.
See `semantic-nonterminal-external-member-children' for details."
  (if (and usedb
	   (fboundp 'semanticdb-minor-mode-p)
	   (semanticdb-minor-mode-p))
      (let ((m (semanticdb-find-nonterminal-external-children-of-type
		(semantic-tag-name token))))
	(if m (apply #'append (mapcar #'cdr m))))
    (semantic-find-nonterminal-by-function
     `(lambda (tok)
	;; This bit of annoying backquote forces the contents of
	;; token into the generated lambda.
       (semantic-nonterminal-external-member-p ',token tok))
     (current-buffer) nil nil)
    ))

(defun semantic-nonterminal-protection (token &optional parent)
  "Return protection information about TOKEN with optional PARENT.
This function returns on of the following symbols:
   nil        - No special protection.  Language dependent.
   'public    - Anyone can access this TOKEN.
   'private   - Only methods in the local scope can access TOKEN.
   'protected - Like private for outside scopes, like public for child
                classes.
Some languages may choose to provide additional return symbols specific
to themselves.  Use of this function should allow for this.

The default behavior (if not overriden with `nonterminal-protection'
is to return a symbol based on type modifiers."
  (let* ((s (semantic-fetch-overload 'nonterminal-protection)))
    (if s (funcall s token parent)
      (semantic-nonterminal-protection-default token parent))))

(defun semantic-nonterminal-protection-default (token &optional parent)
  "Return the protection of TOKEN as a child of PARENT default action.
See `semantic-nonterminal-protection'."
  (let ((mods (semantic-tag-modifiers token))
	(prot nil))
    (while (and (not prot) mods)
      (if (stringp (car mods))
	  (let ((s (car mods)))
	    (setq prot
		  ;; A few silly defaults to get things started.
		  (cond ((or (string= s "public")
			     (string= s "extern")
			     (string= s "export"))
			 'public)
			((string= s "private")
			 'private)
			((string= s "protected")
			 'protected)))))
      (setq mods (cdr mods)))
    prot))

(defun semantic-nonterminal-abstract (token &optional parent)
  "Return non nil if TOKEN is abstract.
Optional PARENT is the parent token of TOKEN.
In UML, abstract methods and classes have special meaning and behavior
in how methods are overriden.  In UML, abstract methods are italicized.

The default behavior (if not overriden with `nonterminal-abstract'
is to return true if `abstract' is in the type modifiers."
  (let* ((s (semantic-fetch-overload 'nonterminal-abstract)))
    (if s (funcall s token parent)
      (semantic-nonterminal-abstract-default token parent))))

(defun semantic-nonterminal-abstract-default (token &optional parent)
  "Return non-nil if TOKEN is abstract as a child of PARENT default action.
See `semantic-nonterminal-abstract'."
  (let ((mods (semantic-tag-modifiers token))
	(abs nil))
    (while (and (not abs) mods)
      (if (stringp (car mods))
	  (setq abs (or (string= (car mods) "abstract")
			(string= (car mods) "virtual"))))
      (setq mods (cdr mods)))
    abs))

(defun semantic-nonterminal-leaf (token &optional parent)
  "Return non nil if TOKEN is leaf.
Optional PARENT is the parent token of TOKEN.
In UML, leaf methods and classes have special meaning and behavior.

The default behavior (if not overriden with `nonterminal-leaf'
is to return true if `leaf' is in the type modifiers."
  (let* ((s (semantic-fetch-overload 'nonterminal-leaf)))
    (if s (funcall s token parent)
      (semantic-nonterminal-leaf-default token parent))))

(defun semantic-nonterminal-leaf-default (token &optional parent)
  "Return non-nil if TOKEN is leaf as a child of PARENT default action.
See `semantic-nonterminal-leaf'."
  (let ((mods (semantic-tag-modifiers token))
	(leaf nil))
    (while (and (not leaf) mods)
      (if (stringp (car mods))
	  ;; Use java FINAL as example default.  There is none
	  ;; for C/C++
	  (setq leaf (string= (car mods) "final")))
      (setq mods (cdr mods)))
    leaf))

(define-overload semantic-nonterminal-static (token &optional parent)
  "Return non nil if TOKEN is static.
Optional PARENT is the parent token of TOKEN.
In UML, static methods and attributes mean that they are allocated
in the parent class, and are not instance specific.
UML notation specifies that STATIC entries are underlined.")

(defun semantic-nonterminal-static-default (token &optional parent)
  "Return non-nil if TOKEN is static as a child of PARENT default action.
See `semantic-nonterminal-static'."
  (let ((mods (semantic-tag-modifiers token))
	(static nil))
    (while (and (not static) mods)
      (if (stringp (car mods))
	  (setq static (string= (car mods) "static")))
      (setq mods (cdr mods)))
    static))

(defun semantic-nonterminal-full-name (token &optional stream-or-buffer)
  "Return the fully qualified name of TOKEN in the package hierarchy.
STREAM-OR-BUFFER can be anything convertable by `semantic-something-to-stream',
but must be a toplevel semantic token stream that contains TOKEN.
A Package Hierarchy is defined in UML by the way classes and methods
are organized on disk.  Some language use this concept such that a
class can be accessed via it's fully qualified name, (such as Java.)
Other languages qualify names within a Namespace (such as C++) which
result in a different package like structure.  Languages which do not
override this function with `nonterminal-full-name' will use
`semantic-token-name'.  Override functions only need to handle
STREAM-OR-BUFFER with a token stream value, or nil."
  (let* ((s (semantic-fetch-overload 'nonterminal-full-name))
	 (stream (semantic-something-to-tag-table (or stream-or-buffer token))))
    (if s (funcall s token stream)
      (semantic-nonterminal-full-name-default token stream))))

(defun semantic-nonterminal-full-name-default (token stream)
  "Default method for `semantic-nonterminal-full-name'.
Return the name of TOKEN found in the toplevel STREAM."
  (semantic-tag-name token))


;;; Do some fancy stuff with overlays
;;
(defun semantic-highlight-token (token &optional face)
  "Specify that TOKEN should be highlighted.
Optional FACE specifies the face to use."
  (let ((o (semantic-tag-overlay token)))
    (semantic-overlay-put o 'old-face
			  (cons (semantic-overlay-get o 'face)
				(semantic-overlay-get o 'old-face)))
    (semantic-overlay-put o 'face (or face 'highlight))
    ))

(defun semantic-unhighlight-token (token)
  "Unhighlight TOKEN, restoring it's previous face."
  (let ((o (semantic-tag-overlay token)))
    (semantic-overlay-put o 'face (car (semantic-overlay-get o 'old-face)))
    (semantic-overlay-put o 'old-face (cdr (semantic-overlay-get o 'old-face)))
    ))

(defun semantic-momentary-unhighlight-token (token)
  "Unhighlight TOKEN, restoring it's previous face."
  (semantic-unhighlight-token token)
  (remove-hook 'pre-command-hook
	       `(lambda () (semantic-momentary-unhighlight-token ',token))))

(defun semantic-momentary-highlight-token (token &optional face)
  "Highlight TOKEN, removing highlighting when the user hits a key.
Optional argument FACE is the face to use for highlighting.
If FACE is not specified, then `highlight' will be used."
  (semantic-highlight-token token face)
  (add-hook 'pre-command-hook
	    `(lambda () (semantic-momentary-unhighlight-token ',token))))

(defun semantic-set-token-face (token face)
  "Specify that TOKEN should use FACE for display."
  (semantic-overlay-put (semantic-tag-overlay token) 'face face))

(defun semantic-set-token-invisible (token &optional visible)
  "Enable the text in TOKEN to be made invisible.
If VISIBLE is non-nil, make the text visible."
  (semantic-overlay-put (semantic-tag-overlay token) 'invisible
			(not visible)))

(defun semantic-token-invisible-p (token)
  "Return non-nil if TOKEN is invisible."
  (semantic-overlay-get (semantic-tag-overlay token) 'invisible))

(defun semantic-set-token-intangible (token &optional tangible)
  "Enable the text in TOKEN to be made intangible.
If TANGIBLE is non-nil, make the text visible.
This function does not have meaning in XEmacs because it seems that
the extent 'intangible' property does not exist."
  (semantic-overlay-put (semantic-tag-overlay token) 'intangible
			(not tangible)))

(defun semantic-token-intangible-p (token)
  "Return non-nil if TOKEN is intangible.
This function does not have meaning in XEmacs because it seems that
the extent 'intangible' property does not exist."
  (semantic-overlay-get (semantic-tag-overlay token) 'intangible))

(defun semantic-overlay-signal-read-only
  (overlay after start end &optional len)
  "Hook used in modification hooks to prevent modification.
Allows deletion of the entire text.
Argument OVERLAY, AFTER, START, END, and LEN are passed in by the system."
  ;; Stolen blithly from cpp.el in Emacs 21.1
  (if (and (not after)
	   (or (< (semantic-overlay-start overlay) start)
	       (> (semantic-overlay-end overlay) end)))
      (error "This text is read only")))

(defun semantic-set-token-read-only (token &optional writable)
  "Enable the text in TOKEN to be made read-only.
Optional argument WRITABLE should be non-nil to make the text writable.
instead of read-only."
  (let ((o (semantic-tag-overlay token))
	(hook (if writable nil '(semantic-overlay-signal-read-only))))
    (if (featurep 'xemacs)
        ;; XEmacs extents have a 'read-only' property.
        (semantic-overlay-put o 'read-only (not writable))
      (semantic-overlay-put o 'modification-hooks hook)
      (semantic-overlay-put o 'insert-in-front-hooks hook)
      (semantic-overlay-put o 'insert-behind-hooks hook))))

(defun semantic-token-read-only-p (token)
  "Return non-nil if the current TOKEN is marked read only."
  (let ((o (semantic-tag-overlay token)))
    (if (featurep 'xemacs)
        ;; XEmacs extents have a 'read-only' property.
        (semantic-overlay-get o 'read-only)
      (member 'semantic-overlay-signal-read-only
              (semantic-overlay-get o 'modification-hooks)))))

(defun semantic-narrow-to-token (token)
  "Narrow to the region specified by TOKEN."
  (narrow-to-region (semantic-tag-start token)
		    (semantic-tag-end token)))

(defmacro semantic-with-buffer-narrowed-to-current-token (&rest body)
  "Execute BODY with the buffer narrowed to the current nonterminal."
  `(save-restriction
     (semantic-narrow-to-token (semantic-current-tag))
     ,@body))
(put 'semantic-with-buffer-narrowed-to-current-token 'lisp-indent-function 0)
(add-hook 'edebug-setup-hook
	  (lambda ()
	    (def-edebug-spec semantic-with-buffer-narrowed-to-current-token
	      (def-body))))

(defmacro semantic-with-buffer-narrowed-to-token (token &rest body)
  "Narrow to TOKEN, and execute BODY."
  `(save-restriction
     (semantic-narrow-to-token ,token)
     ,@body))
(put 'semantic-with-buffer-narrowed-to-token 'lisp-indent-function 1)
(add-hook 'edebug-setup-hook
	  (lambda ()
	    (def-edebug-spec semantic-with-buffer-narrowed-to-token
	      (def-body))))

;;; Interactive Functions for bovination
;;
(defun semantic-describe-token (&optional token)
  "Describe TOKEN in the minibuffer.
If TOKEN is nil, describe the token under the cursor."
  (interactive)
  (if (not token) (setq token (semantic-current-tag)))
  (semantic-bovinate-toplevel t)
  (if token (message (semantic-summarize-nonterminal token))))


;;; Putting keys on tokens.
;;
(defun semantic-add-label (label value &optional token)
  "Add a LABEL with VALUE on TOKEN.
If TOKEN is not specified, use the token at point."
  (interactive "sLabel: \nXValue (eval): ")
  (if (not token)
      (progn
	(semantic-bovinate-toplevel t)
	(setq token (semantic-current-tag))))
  (semantic--tag-put-property token (intern label) value)
  (message "Added label %s with value %S" label value))

(defun semantic-show-label (label &optional token)
  "Show the value of LABEL on TOKEN.
If TOKEN is not specified, use the token at point."
  (interactive "sLabel: ")
  (if (not token)
      (progn
	(semantic-bovinate-toplevel t)
	(setq token (semantic-current-tag))))
  (message "%s: %S" label (semantic--tag-get-property token (intern label))))


;;; Hacks
;;
;; Some hacks to help me test these functions
(defun semantic-current-token (p)
  "Display the curent token.
Argument P is the point to search from in the current buffer."
  (interactive "d")
  (let ((tok (semantic-find-innermost-nonterminal-by-position
	      p (current-buffer))))
    (message (mapconcat 'semantic-abbreviate-nonterminal tok ","))
    (car tok))
  )

(defun semantic-hack-search ()
  "Disply info about something under the cursor using generic methods."
  (interactive)
  (let (
	;(name (thing-at-point 'symbol))
	(strm (cdr (semantic-bovinate-toplevel)))
	(res nil))
;    (if name
	(setq res
;	      (semantic-find-nonterminal-by-name name strm)
;	      (semantic-find-nonterminal-by-type name strm)
;	      (semantic-recursive-find-nonterminal-by-name name (current-buffer))
	      (semantic-brute-find-tag-by-position (point) strm)
	      
	      )
;	)
    (if res
	(progn
	  (pop-to-buffer "*SEMANTIC HACK RESULTS*")
	  (require 'pp)
	  (erase-buffer)
	  (insert (pp-to-string res) "\n")
	  (goto-char (point-min))
	  (shrink-window-if-larger-than-buffer))
      (message "nil"))))

(defun semantic-assert-valid-token (tok)
  "Assert that TOK is a valid token."
  (if (semantic-tag-p tok)
      (if (semantic-tag-with-position-p tok)
	  (let ((o  (semantic-tag-overlay tok)))
	    (if (and (semantic-overlay-p o)
		     (not (semantic-overlay-live-p o)))
		(let ((debug-on-error t))
		  (error "Tag %s is invalid!"))
	      ;; else, tag is OK.
	      ))
	;; Positionless tags are also ok.
	)
    (let ((debug-on-error t))
      (error "Not a semantic tag: %S" tok))))

(defun semantic-sanity-check (&optional cache over notfirst)
  "Perform a sanity check on the current buffer.
The buffer's set of overlays, and those overlays found via the cache
are verified against each other.
CACHE, and OVER are the semantic cache, and the overlay list.
NOTFIRST indicates that this was not the first call in the recursive use."
  (interactive)
  (if (and (not cache) (not over) (not notfirst))
      (setq cache semantic-toplevel-bovine-cache
	    over (semantic-overlays-in (point-min) (point-max))))
  (while cache
    (let ((chil (semantic-tag-components-with-overlays (car cache))))
      (if (not (memq (semantic-tag-overlay (car cache)) over))
	  (message "Tag %s not in buffer overlay list."
		   (semantic-concise-prototype-nonterminal (car cache))))
      (setq over (delq (semantic-tag-overlay (car cache)) over))
      (setq over (semantic-sanity-check chil over t))
      (setq cache (cdr cache))))
  (if (not notfirst)
      ;; Strip out all overlays which aren't semantic overlays
      (let ((o nil))
	(while over
	  (when (and (semantic-overlay-get (car over) 'semantic)
		     (not (eq (semantic-overlay-get (car over) 'semantic)
			      'unmatched)))
	    (setq o (cons (car over) o)))
	  (setq over (cdr over)))
	(message "Remaining overlays: %S" o)))
  over)

(provide 'semantic-util)

;;; Minor modes
;;
(require 'semantic-util-modes)

;;; semantic-util.el ends here
