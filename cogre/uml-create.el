;;; cogre-uml.el --- UML support for COGRE

;;; Copyright (C) 2001 Eric M. Ludlam

;; Author: Eric M. Ludlam <zappo@gnu.org>
;; Keywords: oop, uml
;; X-RCS: $Id: uml-create.el,v 1.2 2001-05-19 22:22:31 zappo Exp $

;; This file is not part of GNU Emacs.

;; This is free software; you can redistribute it and/or modify
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
;; Routines used to create UML diagrams from Semantic generated reverse
;; engineered token databases.

(require 'cogre-uml)
(require 'semantic)
(require 'semanticdb)

;;; Code:
(defclass cogre-semantic-uml-graph (cogre-graph)
  nil
  "This graph is for semantic oriented UML diagrams.")

(defmethod cogre-insert-class-list ((graph cogre-semantic-uml-graph))
  "Return a list of classes GRAPH will accept."
  (append (eieio-build-class-alist 'cogre-link)
	  (eieio-build-class-alist 'cogre-semantic-class)
	  (eieio-build-class-alist 'cogre-package)))

(defclass cogre-semantic-class (cogre-class)
  nil
  "A Class node linked to semantic parsed buffers.
Inherits from the default UML class node type, and adds user
interfacing which links working with this node directly to source
code.")

(defmethod initialize-instance ((this cogre-semantic-class) &optional fields)
  "When interactively creating a class node THIS, query for the class name.
Optional argument FIELDS are not used."
  (call-next-method)
  (if (string-match "^Class[0-9]*" (oref this object-name))
      ;; In this case, we have a default class object-name, so try and query
      ;; for the real class (from sources) which we want to use.
      (let* ((class (or (oref this class) (cogre-read-class-name)))
	     (tok (if (semantic-token-p class)
		      class
		    (cdr (car (semanticdb-find-nonterminal-by-name
			       class nil nil nil t)))))
	     )
	(if (semantic-token-p class) (setq class (semantic-token-name class)))
	(if (and tok (eq (semantic-token-token tok) 'type)
		 (string= (semantic-token-type tok) "class"))
	    (let ((slots (semantic-token-type-parts tok))
		  (extmeth (semanticdb-find-nonterminal-by-extra-spec-value
			    'parent (semantic-token-name tok) nil nil nil t))
		  attrib method)
	      ;; Bin them up
	      (while slots
		(cond
		 ;; A plain string, a simple language, just do attributes.
		 ((stringp (car slots))
		  (setq attrib (cons (list (car slots) 'variable nil)
				     attrib))
		  )
		 ;; Variable decl is an attribute
		 ((eq (semantic-token-token (car slots)) 'variable)
		  (setq attrib (cons (car slots) attrib)))
		 ;; A function decle is a method.
		 ((eq (semantic-token-token (car slots)) 'function)
		  (setq method (cons (car slots) method)))
		 )
		(setq slots (cdr slots)))
	      ;; Add in all those extra methods
	      (while extmeth
		(let ((sl (cdr (car extmeth))))
		  (while sl
		    (if (eq (semantic-token-token (car sl)) 'function)
			(setq method (cons (car sl) method)))
		    (setq sl (cdr sl))))
		(setq extmeth (cdr extmeth)))
	      ;; Put them into the class.
	      (oset this object-name class)
	      (oset this class tok)
	      (oset this attributes (nreverse attrib))
	      (oset this methods (nreverse method))
	      ;; Tada!
	      ))))
  this)

(defmethod cogre-uml-stoken->uml ((class cogre-semantic-class) stoken &optional text)
  "For CLASS convert a Semantic token STOKEN into a uml definition.
Optional TEXT property is passed down."
  (call-next-method class stoken
		    (semantic-uml-abbreviate-nonterminal
		     stoken nil t))
  )

(defmethod cogre-entered ((class cogre-semantic-class) start end)
  "Method called when the cursor enters CLASS.
START and END cover the region with the property."
  (cogre-uml-source-display class (point))
  (call-next-method))

(defmethod cogre-left ((class cogre-semantic-class) start end)
  "Method called when the cursor exits CLASS.
START and END cover the region with the property."
  (call-next-method))

;;; Screen Manager
;;
;; Manage the display of the source buffer somewhere near the class diagram
;; in a nice way.
(defcustom cogre-uml-source-display-method
  'cogre-uml-source-display-bottom
  "A Function called to display a source buffer associated with a Graph.
This function can be anything, or nil, though the following options
are preferred:
 `cogre-uml-source-display-bottom' - in a window on the bottom of the frame.
 `cogre-uml-source-display-top' - in a window on the top of the frame.
The function specified must take a `point-marker' to specify the
location that is to be displayed."
  :group 'cogre
  :type '(choice (const 'cogre-uml-source-display-bottom)
		 (const 'cogre-uml-source-display-top)
		 ))

(defmethod cogre-uml-source-marker ((class cogre-semantic-class) token)
  "Return a marker position for a CLASS containing TOKEN.
This returned marker will be in the source file of the attribute,
method, or class definition.  nil if there is not match."
  (let ((semc (oref class class))
	(p nil))
    (cond ((and token (semantic-token-with-position-p token))
	   (setq p (save-excursion
		     (semantic-find-nonterminal token)
		     (point-marker))
		 ))
	  ((and token (semantic-token-with-position-p semc))
	   (setq p (save-excursion
		     (semantic-find-nonterminal token semc)
		     (point-marker))
		 ))
	  ((and semc (semantic-token-with-position-p semc))
	   (setq p (save-excursion
		     (semantic-find-nonterminal semc)
		     (point-marker))
		 ))
	  (t nil))
    p))

(defmethod cogre-uml-source-display ((class cogre-semantic-class) point)
  "Display source code associated with CLASS based on text at POINT.
The text must be handled by an overlay of some sort which has the
semantic token we need as a property.  If not, then nothing happens.
Uses `cogre-uml-source-display-method'."
  (let* ((sem (get-text-property point 'semantic))
	 (p (cogre-uml-source-marker class sem)))
    (when p
      (save-excursion
	(funcall cogre-uml-source-display-method p))
      ))
  )

(defmethod cogre-activate ((class cogre-semantic-class))
  "Activate CLASS.
This could be as simple as displaying the current state,
customizing the object, or performing some complex task."
  (let* ((sem (get-text-property (point) 'semantic))
	 (p (cogre-uml-source-marker class sem))
	 (cp (point-marker)))
    (if (not p)
	(error "No source to jump to")
      ;; Activating is the reverse of just showing the sorce
      (switch-to-buffer (marker-buffer p))
      (funcall cogre-uml-source-display-method cp)
      ))
  )

(defcustom cogre-uml-source-display-window-size 5
  "Size of same-frame window displaying source code."
  :group 'cogre
  :type 'integer)

(defun cogre-uml-source-display-bottom (m)
  "Display point M in a small buffer on the bottom of the current frame."
  (if (cdr (window-list))
      (cogre-uml-source-display-other-window m)
    (split-window-vertically (- (window-height)
				cogre-uml-source-display-window-size
				1))
    (other-window 1)
    (switch-to-buffer (marker-buffer m) t)
    (recenter 1)
    (goto-char m)
    (other-window -1))
  )

(defun cogre-uml-source-display-other-window (m)
  "Display point M in other window."
  (other-window 1)
  (switch-to-buffer (marker-buffer m) t)
  (goto-char m)
  (recenter 1)
  (other-window -1)
  )

;;; Auto-Graph generation
;;
;; Functions for creating a graph from semantic parts.
(defvar cogre-class-history nil
  "History for inputting class names.")

(defun cogre-read-class-name ()
  "Read in a class name to be used by a cogre node."
  (let ((finddefaultlist (semantic-find-nonterminal-by-overlay))
	class prompt stream
	)
    ;; Assume the top most item is the all encompassing class.
    (if finddefaultlist
	(setq class (car finddefaultlist)))
    ;; Make sure our class is really a class
    (if (not (and
	      class
	      (eq (semantic-token-token class) 'type)
	      (string= (semantic-token-type class) "class")))
	(setq class nil)
      (setq class (semantic-token-name class)))
    ;; Create a prompt
    (setq prompt (if class (concat "Class (default " class "): ") "Class: "))
    ;; Get the stream used for completion.
    (setq stream
	  (apply #'append
		 (mapcar #'cdr
			 (semanticdb-find-nonterminal-by-type
			  "class" nil nil nil t))))
    ;; Do the query
    (completing-read prompt stream
		     nil nil nil 'cogre-class-history
		     class)
    ))

;;;###autoload
(defun cogre-uml-quick-class (class)
  "Create a new UML diagram based on CLASS showing only immediate lineage.
The parent to CLASS, CLASS, and all of CLASSes children will be shown."
  (interactive (list (cogre-read-class-name)))
  (let* ((class-tok (cdr (car (semanticdb-find-nonterminal-by-name
			       class nil nil nil t t))))
	 (class-node nil)
	 (parent (semantic-token-type-parent class-tok))
	 (parent-nodes nil)
	 (children (semanticdb-find-nonterminal-by-function
		    (lambda (stream sp si)
		      (semantic-find-nonterminal-by-function
		       (lambda (tok)
			 (and (eq (semantic-token-token tok) 'type)
			      (member class (semantic-token-type-parent tok))))
		       stream sp si))
		    nil nil nil t t))
	 (children-nodes nil)
	 (ymax 0)
	 (xmax 0)
	 (x-accum 0)
	 (y-accum 0))
    ;; Create a new graph
    (cogre class 'cogre-semantic-uml-graph)
    (goto-char (point-min))
    ;; Create all the parent nodes in the graph, and align them.
    (while parent
      (setq parent-nodes
	    (cons (make-instance 'cogre-semantic-class
				 :position (vector x-accum y-accum)
				 :class (car parent))
		  parent-nodes))
      (cogre-node-rebuild (car parent-nodes))
      (setq x-accum (+ x-accum
		       (length (car (oref (car parent-nodes) rectangle)))
		       cogre-horizontal-margins))
      (setq ymax (max ymax (length (oref (car parent-nodes) rectangle))))
      (setq parent (cdr parent)))
    (setq xmax (- x-accum cogre-horizontal-margins))
    ;; Create this class
    (setq x-accum 0)
    (setq y-accum (+ y-accum ymax cogre-vertical-margins))
    (setq class-node
	  (make-instance 'cogre-semantic-class
			 :position (vector x-accum y-accum)
			 :class class-tok))
    (cogre-node-rebuild class-node)
    (setq ymax (length (oref class-node rectangle)))
    ;; Creawte all the children nodes, and align them.
    (setq x-accum 0)
    (setq y-accum (+ y-accum ymax cogre-vertical-margins))
    (while children
      (let ((c (cdr (car children))))
	(while c
	  (setq children-nodes
		(cons (make-instance 'cogre-semantic-class
				     :position (vector x-accum y-accum)
				     :class (car c))
		      children-nodes))
	  (cogre-node-rebuild (car children-nodes))
	  (setq x-accum (+ x-accum
			   (length (car (oref (car children-nodes) rectangle)))
			   cogre-horizontal-margins))
	  (setq c (cdr c))))
      (setq children (cdr children)))
    (setq xmax (max xmax (- x-accum cogre-horizontal-margins)))
    ;; Center all the nodes to eachother.
    (let ((shift 0)
	  (delta 0)
	  (lines (list parent-nodes
		       (list class-node)
		       children-nodes))
	  (maxn nil)
	  )
      (while lines
	(setq maxn (car (car lines)))
	(when maxn
	  ;;(cogre-node-rebuild maxn)
	  (setq delta (- xmax (aref (oref maxn position) 0)
			 (length (car (oref maxn rectangle)))))
	  (when (> delta 0)
	    (setq shift (/ delta 2))
	    (mapcar (lambda (n) (cogre-move-delta n shift 0))
		    (car lines))))
	(setq lines (cdr lines)))
      )
    ;; Link everyone together
    (let ((n parent-nodes))
      (while n
	(make-instance 'cogre-inherit :start class-node :end (car n))
	(setq n (cdr n)))
      (setq n children-nodes)
      (while n
	(make-instance 'cogre-inherit :start (car n) :end class-node)
	(setq n (cdr n))))
    ;; Refresh the graph
    (cogre-refresh)
    ))

;;;###autoload
(defun cogre-uml-create (class)
  "Create a new UML diagram, with CLASS as the root node.
CLASS must be a type in the current project."
  (interactive (list (cogre-read-class-name)))
  (let ((root (cdr (car (semanticdb-find-nonterminal-by-name class))))
	)
    
    ))

(provide 'uml-create)

;;; uml-create.el ends here
