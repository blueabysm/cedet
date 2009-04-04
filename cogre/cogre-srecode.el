;;; cogre-srecode.el --- SRecode macros for COGRE.
;;
;; Copyright (C) 2009 Eric M. Ludlam
;;
;; Author: Eric M. Ludlam <eric@siege-engine.com>
;; X-RCS: $Id: cogre-srecode.el,v 1.1 2009-04-04 14:46:29 zappo Exp $
;;
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
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:
;;
;; Basic SRecode support for COGRE related activities.

(require 'srecode)

;;; Code:
;;;###autoload
(defun cogre-srecode-setup ()
  "Update various paths to get SRecode to identify COGRE macros."

  ;; Make sure we have a good version of graphviz-dot-mode
  (inversion-require 'graphviz-dot-mode "0.3.2")

  (let* ((lib (locate-library "cogre.el" t))
	 (ededir (file-name-directory lib))
	 (tmpdir (file-name-as-directory
		  (expand-file-name "templates" ededir))))
    (when (not tmpdir)
      (error "Unable to location COGRE Templates directory"))

    ;; Rig up the map.
    (require 'srecode-map)
    (add-to-list 'srecode-map-load-path tmpdir)
    (srecode-map-update-map t)
    
    ))

(defvar cogre-srecode-current-graph nil
  "The current COGRE graph to add to SRecode.")

;;;###autoload
(defun srecode-semantic-handle-:cogre (dict)
  "Add macros to dictionary DICT based on COGRE data."
  (let ((G (if (eieio-object-p cogre-graph)
	       cogre-graph
	     cogre-srecode-current-graph)))
    (when (not G) (error "Cannot resolve :cogre template argument.  No current graph"))

    (srecode-dictionary-set-value dict "GRAPHNAME" (oref G name))

    ;; @todo - set buffer to graph.  Convert to ascii.

    (srecode-dictionary-set-value dict "GRAPH" "")
    ))

;;;###autoload
(eval-after-load "graphviz-dot-mode"
  (cogre-srecode-setup))


;;;###autoload
(defun srecode-semantic-handle-:dot (dict)
  "Add macros to dictionary DICT based on the current DOT buffer."
  ;; @todo - Is there anything??
  
  )

(defun cogre-srecode-add-attr (label value dict)
  "Add LABEL with VALUE to DICT."
  (let ((subdict (srecode-dictionary-add-section-dictionary dict "ATTRIBUTES")))
    (srecode-dictionary-set-value subdict "LABEL" label)
    (srecode-dictionary-set-value subdict "VALUE" value)))

(define-mode-local-override srecode-semantic-apply-tag-to-dict
  graphviz-dot-mode (tagobj dict)
  "Insert features of TAGOBJ into dictionary DICT."
  ;; Semantic Graphviz tags are not like other tags.

  ;; Store the sst into the dictionary.
  (srecode-dictionary-set-value dict "TAG" tagobj)

  ;; Pull out the tag for the individual pieces.
  (let ((tag (oref tagobj :prime)))

    (srecode-dictionary-set-value dict "NAME" (semantic-tag-name tag))

    (cond 
     ((semantic-tag-of-class-p tag 'node)
      (let ((A (semantic-tag-get-attribute tag :attributes)))
	(while A
	  (cogre-srecode-add-attr (substring (symbol-name (car A)) 1)
				  (car (cdr A))
				  dict)
	  (setq A (cdr (cdr A)))))				
      )
     ((semantic-tag-of-class-p tag 'link)
      (srecode-dictionary-set-value
       dict "TAIL" (semantic-tag-get-attribute tag :to))
      ;(cogre-srecode-add-attr "arrowhead" (semantic-tag-get-attribute tag :arrowhead) dict)
      ;(cogre-srecode-add-attr "arrowtail" (semantic-tag-get-attribute tag :arrowtail) dict)
      (let ((A (semantic-tag-get-attribute tag :attributes)))
	(while A
	  (cogre-srecode-add-attr (substring (symbol-name (car A)) 1)
				  (car (cdr A))
				  dict)
	  (setq A (cdr (cdr A)))))
      )
     )
    ))

(provide 'cogre-srecode)
;;; cogre-srecode.el ends here
